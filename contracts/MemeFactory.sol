// ███╗░░░███╗███████╗███╗░░░███╗███████╗  ███████╗░█████╗░░█████╗░████████╗░█████╗░██████╗░██╗░░░██╗
// ████╗░████║██╔════╝████╗░████║██╔════╝  ██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗╚██╗░██╔╝
// ██╔████╔██║█████╗░░██╔████╔██║█████╗░░  █████╗░░███████║██║░░╚═╝░░░██║░░░██║░░██║██████╔╝░╚████╔╝░
// ██║╚██╔╝██║██╔══╝░░██║╚██╔╝██║██╔══╝░░  ██╔══╝░░██╔══██║██║░░██╗░░░██║░░░██║░░██║██╔══██╗░░╚██╔╝░░
// ██║░╚═╝░██║███████╗██║░╚═╝░██║███████╗  ██║░░░░░██║░░██║╚█████╔╝░░░██║░░░╚█████╔╝██║░░██║░░░██║░░░
// ╚═╝░░░░░╚═╝╚══════╝╚═╝░░░░░╚═╝╚══════╝  ╚═╝░░░░░╚═╝░░╚═╝░╚════╝░░░░╚═╝░░░░╚════╝░╚═╝░░╚═╝░░░╚═╝░░░

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaporDEXFactory} from "./interfaces/IVaporDEXFactory.sol";
import {IVaporDEXRouter} from "./interfaces/IVaporDEXRouter.sol";
import {Token} from "./Token.sol";
import {ISablierV2LockupLinear} from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import {LockupLinear} from "@sablier/v2-core/src/types/DataTypes.sol";
import {IDexAggregator} from "./interfaces/IDexAggregator.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

error MemeFactory__WrongConstructorArguments();
error MemeFactory__LiquidityLockedOrDepleted();
error MemeFactory__Unauthorized();
error MemeFactory__ZeroAddress();
error MemeFactory__WrongLaunchArguments();
error MemeFactory__InsufficientBalance();
error MemeFactory__Invalid();
error MemeFactory__TranferFailed(address);
error MemeFactory__NotEnoughLiquidity();
error MemeFactory__MinimumLockDuration();

/// @title MemeFactory
/// @author Roy & Jose
/// @notice This contract is used to launch new tokens and create liquidity for them
/// @dev Utilizes 'Sablier' for liquidity locking

contract MemeFactory is Ownable {
    //////////////
    /// EVENTS ///
    //////////////

    event TokenLaunched(
        address indexed _tokenAddress,
        address indexed _pairAddress,
        bool _liquidityBurned
    );

    event StreamCreated(uint256 indexed _streamId);
    event LiquidityBurned(
        address indexed pair,
        address indexed _burner,
        uint256 _amount
    );
    event LiquidityTokensUnlocked(
        address indexed _pairAddress,
        address indexed _receiver
    );
    event LiquidityTransferred(
        address indexed _pairAddress,
        address indexed _to
    );
    event LaunchFeeUpdated(uint256 _newFee);
    event MinimumLiquidityETHUpdated(uint256 _newFee);
    event MinimumLockDurationUpdated(uint40 _newFee);
    event VaporDEXAdapterUpdated(address _newAdapter);
    event AccumulatedFeesWithdrawn(address _to, uint256 _amount);

    ///////////////
    /// STORAGE ///
    ///////////////
    address private immutable factory;
    address private immutable router;
    address private immutable stratosphere;
    IDexAggregator private immutable vaporDexAggregator;
    INonfungiblePositionManager private immutable nonFungiblePositionManager;
    IERC20 private immutable WETH;
    IERC20 private immutable USDC;
    IERC20 private immutable VAPE;
    address private vaporDexAdapter;
    address private teamMultisig;
    uint256 private launchFee;
    uint256 public minLiquidityETH;
    uint40 public minLockDuration;

    // Sablier
    ISablierV2LockupLinear private immutable sablier;
    // Mapping to store the streamId for each pair and lp owner
    mapping(address => mapping(address => uint256)) private liquidityLocks;

    /**
     * @dev MemeFactory constructor initializes the contract with required parameters.
     * @param owner Address of the contract owner.
     * @param routerAddress Address of the VaporDEXRouter contract.
     * @param stratosphereAddress Address of the Stratosphere contract.
     * @param vaporDexAggregator Address of the VaporDEX aggregator.
     * @param vaporDexAdapter Address of the VaporDEX adapter.
     * @param usdc Address of the USDC token.
     * @param vape Address of the VAPE token.
     * @param launchFee Launch fee in USDC.
     * @param uint256 minLiquidityETH;
     * @param uint40 minLockDuration;
     * @param sablier Address of the Sablier contract.
     * @param nonFungiblePositionManager Uni v3 NFT Position Manager
     * @param teamMultisig Multisig address
     */
    struct DeployArgs {
        address owner;
        address routerAddress;
        address stratosphereAddress;
        address vaporDexAggregator;
        address vaporDexAdapter;
        address usdc;
        address vape;
        uint256 launchFee;
        uint256 minLiquidityETH;
        uint40 minLockDuration;
        address sablier;
        address nonFungiblePositionManager;
        address teamMultisig;
    }

    /////////////////////////
    ////// CONSTRUCTOR /////
    ////////////////////////

    constructor(DeployArgs memory args) Ownable(args.owner) {
        // Check for valid constructor arguments
        if (
            args.owner == address(0) ||
            args.routerAddress == address(0) ||
            args.stratosphereAddress == address(0) ||
            args.vaporDexAggregator == address(0) ||
            args.vaporDexAdapter == address(0) ||
            args.usdc == address(0) ||
            args.launchFee == 0 ||
            args.sablier == address(0) ||
            args.minLiquidityETH == 0 ||
            args.minLockDuration == 0
        ) {
            revert MemeFactory__WrongConstructorArguments();
        }

        // Initialize variables
        router = args.routerAddress;
        IVaporDEXRouter _router = IVaporDEXRouter(args.routerAddress);
        factory = _router.factory();
        WETH = IERC20(_router.WETH());
        USDC = IERC20(args.usdc);
        VAPE = IERC20(args.vape);
        minLiquidityETH = args.minLiquidityETH;
        minLockDuration = args.minLockDuration;
        stratosphere = args.stratosphereAddress;
        vaporDexAggregator = IDexAggregator(args.vaporDexAggregator);
        vaporDexAdapter = args.vaporDexAdapter;
        launchFee = args.launchFee;
        sablier = ISablierV2LockupLinear(args.sablier);
        nonFungiblePositionManager = INonfungiblePositionManager(
            args.nonFungiblePositionManager
        );
        teamMultisig = args.teamMultisig;
    }

    /**
     * @dev Launches a new token with specified parameters.
     * @param _name Name of the token.
     * @param _symbol Symbol of the token.
     * @param _totalSupply Total supply of the token.
     * @param _tradingStartsAt Timestamp when trading starts for the token.
     * @param lockDuration Number of days to lock liquidity for.
     * @param _burnLiquidity Flag indicating whether to burn liquidity or lock it.
     * @return _pair Address of the created token pair.
     * @return _tokenAddress Address of the launched token.
     * @return streamId Stream ID if liquidity is locked, otherwise 0.
     */

    function launch(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _tradingStartsAt,
        uint40 lockDuration,
        bool _burnLiquidity
    )
        external
        payable
        returns (address _pair, address _tokenAddress, uint256 streamId)
    {
        uint256 value = msg.value;
        if (value < minLiquidityETH) {
            revert MemeFactory__NotEnoughLiquidity();
        }
        // Step 0: Transfer Fee
        _transferLaunchFee(msg.sender);

        // Step 1: Create the token
        Token _token = _createToken(
            _name,
            _symbol,
            _totalSupply,
            _tradingStartsAt,
            address(vaporDexAggregator),
            vaporDexAdapter
        );
        _tokenAddress = address(_token);

        // Step 2: Create the pair
        IVaporDEXFactory _factory = IVaporDEXFactory(factory);
        _pair = _factory.createPair(_tokenAddress, address(WETH));
        _token.approve(router, _totalSupply);
        _token.approve(_pair, _totalSupply);

        // Step 2: Add Liquidity
        IVaporDEXRouter _router = IVaporDEXRouter(router);
        _router.addLiquidityETH{value: value}(
            _tokenAddress,
            _totalSupply,
            _totalSupply,
            value,
            address(this),
            block.timestamp + 10 minutes
        );
        // Step 3: Get the pair address
        _pair = IVaporDEXFactory(factory).getPair(_tokenAddress, address(WETH));
        if (_pair == address(0)) {
            revert MemeFactory__ZeroAddress();
        }
        // Step 4: Set the LP address in the token
        _token.setLiquidityPool(_pair);
        // Step 5: Renounce ownership of the token
        _token.renounceOwnership();

        // Step 6: Lock Or Burn Liquidity

        IERC20 _lpToken = IERC20(_pair);

        if (_burnLiquidity) {
            // Burn Liquidity
            _lpToken.transfer(address(0), _lpToken.balanceOf(address(this)));
            emit LiquidityBurned(
                _pair,
                msg.sender,
                _lpToken.balanceOf(address(this))
            );
        } else {
            if (lockDuration < minLockDuration) {
                revert MemeFactory__MinimumLockDuration();
            }
            _lpToken.approve(
                address(sablier),
                _lpToken.balanceOf(address(this))
            );
            // Lock Liquidity
            // SablierV2
            LockupLinear.CreateWithDurations memory params;

            // Declare the function parameters
            params.sender = address(this); // The sender will be able to cancel the stream
            params.recipient = msg.sender; // The recipient of the streamed assets
            params.totalAmount = uint128(_lpToken.balanceOf(address(this))); // Total amount is the amount inclusive of all fees
            params.asset = _lpToken; // The streaming asset
            params.cancelable = false; // Whether the stream will be cancelable or not
            params.transferable = true; // Whether the stream will be transferrable or not
            params.durations = LockupLinear.Durations({
                cliff: lockDuration * 1 days - 1 seconds, // Assets will be unlocked only after the cliff period
                total: lockDuration * 1 days
            });

            // Create the stream
            streamId = sablier.createWithDurations(params);
            liquidityLocks[msg.sender][_pair] = streamId;

            emit StreamCreated(streamId);
        }

        // Step 7: Buy VAPE with USDC on VaporDEXAggregator

        _buyVapeWithUsdc(launchFee / 2); // 50% of the launch fee, Admin can change launchFee but this will always be 50% of the launch fee

        // Step 8: Add Liquidity on VAPE/USDC Pair VaporDEXV2

        _addLiquidityVapeUsdc(); // Uses the balance of VAPE and USDC in the contract

        emit TokenLaunched(_tokenAddress, _pair, _burnLiquidity);
    }

    /**
     * @dev Unlocks liquidity tokens for the specified pair and recipient.
     * @param _pair Address of the token pair.
     * @param _receiver Address of the recipient of unlocked tokens.
     * @notice It is recommended to direct the user to Sablier UI for better error handling.
     */
    function unlockLiquidityTokens(address _pair, address _receiver) external {
        if (_receiver == address(0)) {
            revert MemeFactory__ZeroAddress();
        }
        uint256 streamId = liquidityLocks[msg.sender][_pair];

        if (streamId == 0) {
            revert MemeFactory__Unauthorized();
        }

        uint256 withdrawableAmount = sablier.withdrawableAmountOf(streamId);
        if (withdrawableAmount == 0) {
            revert MemeFactory__LiquidityLockedOrDepleted();
        }

        sablier.withdrawMax({streamId: streamId, to: _receiver}); // Other reverts are handled by Sablier

        emit LiquidityTokensUnlocked(_pair, _receiver);
    }

    /**
     * @dev Transfers the locked liquidity to the specified recipient for the given pair.
     * @param _pair Address of the token pair.
     * @param _to Address of the recipient.
     */
    function transferLock(address _pair, address _to) external {
        uint256 streamId = liquidityLocks[msg.sender][_pair];
        if (
            streamId == 0 ||
            _to == address(0) ||
            sablier.isTransferable(streamId) == false
        ) {
            revert MemeFactory__Unauthorized();
        }

        liquidityLocks[_to][_pair] = streamId;
        liquidityLocks[msg.sender][_pair] = 0;

        sablier.transferFrom({from: msg.sender, to: _to, tokenId: streamId}); // Other reverts are handled by Sablier

        emit LiquidityTransferred(_pair, _to);
    }

    /**
     * @dev Sets the minimum liquidity for creating new tokens.
     * @param _liquidity New liquidity.
     */

    function setMinimumLiquidityETH(uint256 _liquidity) external onlyOwner {
        if (_liquidity == 0) {
            revert MemeFactory__Invalid();
        }
        minLiquidityETH = _liquidity;
        emit MinimumLiquidityETHUpdated(_liquidity);
    }

    /**
     * @dev Sets the minimum liquidity for creating new tokens.
     * @param _lockDuration New lock duration in days.
     */

    function setMinLockDuration(uint40 _lockDuration) external onlyOwner {
        if (_lockDuration == 0) {
            revert MemeFactory__Invalid();
        }
        minLockDuration = _lockDuration;
        emit MinimumLockDurationUpdated(_lockDuration);
    }

    /**
     * @dev Sets the launch fee for creating new tokens.
     * @param _launchFee New launch fee in USDC.
     */

    function setLaunchFee(uint256 _launchFee) external onlyOwner {
        if (_launchFee == 0) {
            revert MemeFactory__Invalid();
        }
        launchFee = _launchFee;
        emit LaunchFeeUpdated(_launchFee);
    }

    /**
     * @dev Sets the VaporDEX adapter address.
     * @param _vaporDexAdapter New VaporDEX adapter address.
     */

    function setVaporDEXAdapter(address _vaporDexAdapter) external onlyOwner {
        if (
            _vaporDexAdapter == vaporDexAdapter ||
            _vaporDexAdapter == address(0)
        ) {
            revert MemeFactory__Invalid();
        }
        vaporDexAdapter = _vaporDexAdapter;
        emit VaporDEXAdapterUpdated(_vaporDexAdapter);
    }

    /**
     * @dev Withdraws any remaining USDC fees to the specified address.
     * @param _to Address to which the remaining fees are withdrawn.
     */

    function withdrawFee(address _to) external onlyOwner {
        if (_to == address(0)) {
            revert MemeFactory__ZeroAddress();
        }
        IERC20 _usdc = IERC20(USDC);
        _usdc.transfer(_to, _usdc.balanceOf(address(this)));
        emit AccumulatedFeesWithdrawn(_to, _usdc.balanceOf(address(this)));
    }

    /**
     * @dev Creates a new Token contract with specified parameters.
     * @param name Name of the token.
     * @param symbol Symbol of the token.
     * @param totalSupply Total supply of the token.
     * @param _tradingStartsAt Timestamp when trading starts for the token.
     * @param dexAggregator Address of the decentralized exchange aggregator.
     * @param dexAdapter Address of the decentralized exchange adapter.
     * @return _token Instance of the created Token contract.
     */
    function _createToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 _tradingStartsAt,
        address dexAggregator,
        address dexAdapter
    ) internal returns (Token _token) {
        if (totalSupply == 0 || _tradingStartsAt < block.timestamp + 2 days) {
            revert MemeFactory__WrongLaunchArguments();
        }
        _token = new Token(
            name,
            symbol,
            totalSupply,
            stratosphere,
            address(this),
            _tradingStartsAt,
            dexAggregator,
            dexAdapter
        );
    }

    /**
     * @dev Transfers the launch fee in USDC from the sender.
     * @param _from Address from which the launch fee is transferred.
     */

    function _transferLaunchFee(address _from) internal {
        IERC20 _usdc = IERC20(USDC);
        if (_usdc.balanceOf(_from) < launchFee) {
            revert MemeFactory__InsufficientBalance();
        }
        bool isSuccess = _usdc.transferFrom(_from, address(this), launchFee);
        if (!isSuccess) {
            revert MemeFactory__TranferFailed(_from);
        }
    }

    /**
     * @dev Buys VAPE with USDC on VaporDEXAggregator
     * @param amountIn Amount of USDC to be used for buying VAPE.
     */

    function _buyVapeWithUsdc(uint256 amountIn) internal {
        USDC.approve(address(vaporDexAggregator), amountIn);

        IDexAggregator.FormattedOffer memory offer = vaporDexAggregator
            .findBestPath(
                amountIn,
                address(USDC),
                address(VAPE),
                1 // can be changed to 3
            );
        IDexAggregator.Trade memory trade;
        trade.amountIn = amountIn;
        trade.amountOut = offer.amounts[offer.amounts.length - 1];
        trade.path = offer.path;
        trade.adapters = offer.adapters;
        vaporDexAggregator.swapNoSplit(trade, address(this), 0);
    }

    /**
     * @dev Adds liquidity for VAPE/USDC pair on VaporDEXV2.
     * @notice Uses the balance of VAPE and USDC in the contract.
     */

    function _addLiquidityVapeUsdc() internal {
        uint256 amountInUSDC = USDC.balanceOf(address(this));
        uint256 amountInVAPE = VAPE.balanceOf(address(this));
        USDC.approve(address(nonFungiblePositionManager), amountInUSDC);
        VAPE.approve(address(nonFungiblePositionManager), amountInVAPE);
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
                token0: address(VAPE),
                token1: address(USDC),
                fee: 3000,
                tickLower: -887220, // full range
                tickUpper: 887220, // full range
                amount0Desired: amountInVAPE,
                amount1Desired: amountInUSDC,
                amount0Min: amountInVAPE - _percentage(amountInVAPE, 200), // 2% slippage
                amount1Min: amountInUSDC - _percentage(amountInUSDC, 200), // 2% slippage
                recipient: teamMultisig,
                deadline: block.timestamp + 2 minutes
            });
        nonFungiblePositionManager.mint(mintParams);

        // Q: What checks should be done with the return values?
    }

    function _percentage(
        uint256 _number,
        uint256 _percentageBasisPoints // Example: 1% is 100
    ) internal pure returns (uint256) {
        return (_number * _percentageBasisPoints) / 10_000;
    }

    // Getters

    /**
     * @dev Returns the launch fee.
     * @return uint256 The launch fee.
     */
    function getLaunchFee() external view returns (uint256) {
        return launchFee;
    }

    /**
     * @dev Returns the address of the VaporDEX adapter.
     * @return address The address of the VaporDEX adapter.
     */
    function getVaporDexAdapter() external view returns (address) {
        return vaporDexAdapter;
    }

    /**
     * @dev Returns the address of the VaporDEX router.
     * @return address The address of the VaporDEX router.
     */
    function getVaporDEXRouter() external view returns (address) {
        return router;
    }

    /**
     * @dev Returns the address of the VaporDEX factory.
     * @return address The address of the VaporDEX factory.
     */
    function getVaporDEXFactory() external view returns (address) {
        return factory;
    }

    /**
     * @dev Returns the address of the Stratosphere contract.
     * @return address The address of the Stratosphere contract.
     */
    function getStratosphere() external view returns (address) {
        return stratosphere;
    }

    /**
     * @dev Returns the address of the VaporDEX aggregator.
     * @return address The address of the VaporDEX aggregator.
     */
    function getVaporDexAggregator() external view returns (address) {
        return address(vaporDexAggregator);
    }

    /**
     * @dev Returns the address of the USDC token.
     * @return address The address of the USDC token.
     */
    function getUSDC() external view returns (address) {
        return address(USDC);
    }

    /**
     * @dev Returns the address of the VAPE token.
     * @return address The address of the VAPE token.
     */
    function getVAPE() external view returns (address) {
        return address(VAPE);
    }

    /**
     * @dev Returns the address of the VaporDEX adapter.
     * @return address The address of the VaporDEX adapter.
     */
    function getVaporDEXAdapter() external view returns (address) {
        return vaporDexAdapter;
    }

    /**
     * @dev Returns the address of the team multisig wallet.
     * @return address The address of the team multisig wallet.
     */
    function getTeamMultisig() external view returns (address) {
        return teamMultisig;
    }

    /**
     * @dev Returns the address of the Sablier contract.
     * @return address The address of the Sablier contract.
     */
    function getSablier() external view returns (address) {
        return address(sablier);
    }

    /**
     * @dev Returns the address of the NonFungiblePositionManager contract.
     * @return address The address of the NonFungiblePositionManager contract.
     */
    function getNonFungiblePositionManager() external view returns (address) {
        return address(nonFungiblePositionManager);
    }

    /**
     * @dev Returns the liquidity lock for the specified pair and owner.
     * @param _pair Address of the token pair.
     * @param _owner Address of the owner.
     * @return uint256 Stream ID for the liquidity lock.
     */

    function getLiquidityLock(
        address _pair,
        address _owner
    ) external view returns (uint256) {
        return liquidityLocks[_owner][_pair];
    }
}
