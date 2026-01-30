// Browser console script to intercept and decode Samsara transactions
// Run this in the browser console on https://samsara.nirvana.finance
//
// Usage:
// 1. Open https://samsara.nirvana.finance in your browser
// 2. Connect your wallet
// 3. Open browser DevTools (F12) and go to Console tab
// 4. Paste this entire script and press Enter
// 5. Try to execute a transaction (buy navSOL, sell, stake, etc.)
// 6. The transaction will be intercepted and decoded in the console
// 7. Copy the JSON output for analysis

console.log('🔍 Samsara Transaction Interceptor Started');

// Program IDs to watch for
const SAMSARA_PROGRAM_ID = 'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7';
const MAYFLOWER_PROGRAM_ID = 'AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v';
const COMPUTE_BUDGET_PROGRAM = 'ComputeBudget111111111111111111111111111111';
const TOKEN_PROGRAM = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const ASSOCIATED_TOKEN_PROGRAM = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';

// Known token mints
const KNOWN_TOKENS = {
    'So11111111111111111111111111111111111111112': 'SOL',
    'navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo': 'navSOL',
    'A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS': 'ZEC',
    'navZyeDnqgHBJQjHX8Kk7ZEzwFgDXxVJBcsAXd76gVe': 'navZEC',
    'CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N': 'prANA',
    'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v': 'USDC',
};

// Known market accounts
const KNOWN_ACCOUNTS = {
    '4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc': 'navSOL Samsara Market',
    'A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc': 'navSOL Mayflower Market',
    'DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj': 'navSOL Market Metadata',
    'Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC': 'navSOL Market Group',
    'HeTHfJCgHxpb1snGC5mk8M7bzs99kYAeMBuk9qHd3tMd': 'navSOL Lookup Table',
    '9JiASAyMBL9riFDPJtWCEtK4E2rr2Yfpqxoynxa3XemE': 'navZEC Samsara Market',
    '9SBSQvx5B8tKRgtYa3tyXeyvL3JMAZiA2JVXWzDnFKig': 'navZEC Mayflower Market',
    'HcGpdC8EtNpZPComvRaXDQtGHLpCFXMqfzRYeRSPCT5L': 'navZEC Market Metadata',
    '81JEJdJSZbaXixpD8WQSBWBfkDa6m6KpXpSErzYUHq6z': 'Mayflower Tenant',
    'FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskTC': 'Samsara Tenant',
    'SiDxZaBNqVDCDxvVvXoGMLwLhzSbLVtaQing4RtPpDN': 'Tenant Admin',
};

// Storage for discovered discriminators
const discoveredDiscriminators = {};

// Helper to convert Uint8Array to hex string
function uint8ArrayToHex(uint8Array) {
    return Array.from(uint8Array)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}

// Helper to get label for an account
function getAccountLabel(pubkey) {
    const addr = pubkey.toString();
    if (KNOWN_TOKENS[addr]) return `[${KNOWN_TOKENS[addr]}]`;
    if (KNOWN_ACCOUNTS[addr]) return `[${KNOWN_ACCOUNTS[addr]}]`;
    return '';
}

// Helper to decode versioned transaction
function decodeVersionedTransaction(tx, operationType = 'unknown') {
    console.log('📦 Versioned Transaction Detected');
    console.log(`🎯 Operation Type: ${operationType}`);

    const message = tx.message;
    if (!message) {
        console.log('❌ No message found in transaction');
        return null;
    }

    // Extract static account keys
    const accounts = message.staticAccountKeys || [];
    console.log(`\n📑 Static Accounts (${accounts.length} total):`);
    accounts.forEach((acc, i) => {
        const label = getAccountLabel(acc);
        console.log(`  ${i}: ${acc.toString()} ${label}`);
    });

    // Check for address lookup tables
    if (message.addressTableLookups && message.addressTableLookups.length > 0) {
        console.log(`\n📖 Address Lookup Tables (${message.addressTableLookups.length}):`);
        message.addressTableLookups.forEach((lookup, i) => {
            console.log(`  Table ${i}: ${lookup.accountKey.toString()}`);
            console.log(`    Writable indexes: [${lookup.writableIndexes.join(', ')}]`);
            console.log(`    Readonly indexes: [${lookup.readonlyIndexes.join(', ')}]`);
        });
    }

    // Decode compiled instructions
    const instructions = message.compiledInstructions || [];
    console.log(`\n📋 Instructions (${instructions.length} total):`);

    const decodedInstructions = [];

    instructions.forEach((ix, i) => {
        console.log(`\n🔸 Instruction ${i}:`);

        // Program ID is at the programIdIndex
        const programId = accounts[ix.programIdIndex]?.toString();
        console.log(`  Program: ${programId}`);

        let programName = 'Unknown';
        if (programId === SAMSARA_PROGRAM_ID) programName = 'SAMSARA';
        else if (programId === MAYFLOWER_PROGRAM_ID) programName = 'MAYFLOWER';
        else if (programId === COMPUTE_BUDGET_PROGRAM) programName = 'ComputeBudget';
        else if (programId === TOKEN_PROGRAM) programName = 'Token';
        else if (programId === ASSOCIATED_TOKEN_PROGRAM) programName = 'AssociatedToken';

        console.log(`  Program Name: ${programName}`);

        // Decode account indices
        console.log(`  Accounts (${ix.accountKeyIndexes.length}):`);
        const accountList = [];
        ix.accountKeyIndexes.forEach((accIndex, j) => {
            const pubkey = accounts[accIndex]?.toString() || `[LookupTable:${accIndex}]`;
            const label = getAccountLabel({ toString: () => pubkey });
            console.log(`    ${j}: [${accIndex}] ${pubkey} ${label}`);
            accountList.push({ index: accIndex, pubkey, label });
        });

        // Decode instruction data
        const dataHex = uint8ArrayToHex(ix.data);
        console.log(`  Data (hex): ${dataHex}`);
        console.log(`  Data (length): ${ix.data.length} bytes`);

        // Extract discriminator (first 8 bytes)
        const discriminator = Array.from(ix.data.slice(0, 8));
        console.log(`  Discriminator: [${discriminator.join(', ')}]`);

        // If Samsara or Mayflower program, try to decode further
        if (programId === SAMSARA_PROGRAM_ID || programId === MAYFLOWER_PROGRAM_ID) {
            const discrimKey = `${programName}:${discriminator.join(',')}`;

            // Store discovered discriminator
            if (!discoveredDiscriminators[discrimKey]) {
                discoveredDiscriminators[discrimKey] = {
                    program: programName,
                    discriminator: discriminator,
                    operation: operationType,
                    accountCount: ix.accountKeyIndexes.length,
                    dataLength: ix.data.length,
                    firstSeen: new Date().toISOString()
                };
                console.log(`  🆕 NEW DISCRIMINATOR DISCOVERED!`);
            }

            // Try to decode amounts (assuming u64 little-endian after discriminator)
            if (ix.data.length >= 16) {
                try {
                    const amount1 = new DataView(ix.data.buffer, ix.data.byteOffset + 8, 8).getBigUint64(0, true);
                    console.log(`  Amount 1: ${amount1} (raw)`);
                    console.log(`           ${Number(amount1) / 1e9} (if 9 decimals - SOL/navSOL)`);
                    console.log(`           ${Number(amount1) / 1e6} (if 6 decimals - USDC)`);

                    if (ix.data.length >= 24) {
                        const amount2 = new DataView(ix.data.buffer, ix.data.byteOffset + 16, 8).getBigUint64(0, true);
                        console.log(`  Amount 2: ${amount2} (raw)`);
                    }
                } catch (e) {
                    console.log(`  ⚠️ Could not decode amounts: ${e.message}`);
                }
            }
        }

        // Check for compute budget instructions
        if (programId === COMPUTE_BUDGET_PROGRAM) {
            if (ix.data[0] === 0) {
                const units = new DataView(ix.data.buffer, ix.data.byteOffset + 1, 4).getUint32(0, true);
                console.log(`  ✅ Set Compute Unit Limit: ${units}`);
            } else if (ix.data[0] === 3) {
                const microLamports = new DataView(ix.data.buffer, ix.data.byteOffset + 1, 8).getBigUint64(0, true);
                console.log(`  ✅ Set Compute Unit Price: ${microLamports} microLamports`);
            }
        }

        decodedInstructions.push({
            index: i,
            programId: programId,
            programName: programName,
            programIdIndex: ix.programIdIndex,
            accounts: accountList,
            data: dataHex,
            discriminator: discriminator,
            dataLength: ix.data.length
        });
    });

    console.log(`\n🔗 Recent Blockhash: ${message.recentBlockhash}`);

    // Create comprehensive output
    const output = {
        operationType: operationType,
        timestamp: new Date().toISOString(),
        accounts: accounts.map((a, i) => ({
            index: i,
            pubkey: a.toString(),
            label: getAccountLabel(a)
        })),
        addressTableLookups: message.addressTableLookups?.map(lookup => ({
            accountKey: lookup.accountKey.toString(),
            writableIndexes: Array.from(lookup.writableIndexes),
            readonlyIndexes: Array.from(lookup.readonlyIndexes)
        })) || [],
        instructions: decodedInstructions,
        recentBlockhash: message.recentBlockhash
    };

    console.log('\n📋 Copyable JSON:');
    console.log(JSON.stringify(output, null, 2));

    // Print Samsara/Mayflower specific instructions separately
    const protocolInstructions = decodedInstructions.filter(ix =>
        ix.programId === SAMSARA_PROGRAM_ID || ix.programId === MAYFLOWER_PROGRAM_ID
    );

    if (protocolInstructions.length > 0) {
        console.log('\n🎯 Protocol Instructions Summary:');
        protocolInstructions.forEach(ix => {
            console.log(`\n${ix.programName} Instruction:`);
            console.log(`  Discriminator: [${ix.discriminator.join(', ')}]`);
            console.log(`  Account count: ${ix.accounts.length}`);
            console.log(`  Data length: ${ix.dataLength} bytes`);
            console.log('  Accounts:');
            ix.accounts.forEach((acc, i) => {
                console.log(`    ${i}: ${acc.pubkey} ${acc.label}`);
            });
        });
    }

    return output;
}

// Track what operation the user is trying to do
let pendingOperationType = 'unknown';

// Intercept fetch to detect operation type from API calls
const originalFetch = window.fetch;
window.fetch = async function(...args) {
    const url = args[0]?.toString() || '';

    // Try to detect operation type from URL or request body
    if (url.includes('buy') || url.includes('purchase')) pendingOperationType = 'buy';
    else if (url.includes('sell')) pendingOperationType = 'sell';
    else if (url.includes('stake') || url.includes('deposit')) pendingOperationType = 'stake';
    else if (url.includes('unstake') || url.includes('withdraw')) pendingOperationType = 'unstake';
    else if (url.includes('borrow')) pendingOperationType = 'borrow';
    else if (url.includes('repay')) pendingOperationType = 'repay';
    else if (url.includes('claim')) pendingOperationType = 'claim';

    return originalFetch.apply(this, args);
};

// Monitor click events to detect operation type
document.addEventListener('click', (e) => {
    const text = (e.target.textContent || '').toLowerCase();
    const className = (e.target.className || '').toLowerCase();

    if (text.includes('buy') || className.includes('buy')) pendingOperationType = 'buy';
    else if (text.includes('sell') || className.includes('sell')) pendingOperationType = 'sell';
    else if (text.includes('stake') || className.includes('stake')) pendingOperationType = 'stake';
    else if (text.includes('unstake') || className.includes('unstake')) pendingOperationType = 'unstake';
    else if (text.includes('borrow') || className.includes('borrow')) pendingOperationType = 'borrow';
    else if (text.includes('repay') || className.includes('repay')) pendingOperationType = 'repay';
    else if (text.includes('claim') || className.includes('claim')) pendingOperationType = 'claim';
}, true);

// Store original methods
const wallet = window.solana || window.phantom?.solana || window.solflare;
if (!wallet) {
    console.error('❌ No Solana wallet found! Please connect a wallet first.');
} else {
    const originalSignTransaction = wallet.signTransaction;
    const originalSignAllTransactions = wallet.signAllTransactions;
    const originalSignAndSendTransaction = wallet.signAndSendTransaction;

    // Override signTransaction
    if (originalSignTransaction) {
        wallet.signTransaction = async function(transaction) {
            console.log('\n' + '='.repeat(60));
            console.log('✍️ INTERCEPTED signTransaction');
            console.log(`🎯 Detected operation: ${pendingOperationType}`);
            console.log('='.repeat(60));

            if (transaction.version !== undefined || transaction.message) {
                decodeVersionedTransaction(transaction, pendingOperationType);
            } else {
                console.log('Legacy transaction format - attempting decode...');
                console.log(transaction);
            }

            // Reset operation type
            pendingOperationType = 'unknown';

            throw new Error('Transaction intercepted for analysis - check console for details');
        };
    }

    // Override signAllTransactions
    if (originalSignAllTransactions) {
        wallet.signAllTransactions = async function(transactions) {
            console.log('\n' + '='.repeat(60));
            console.log('✍️ INTERCEPTED signAllTransactions');
            console.log(`Number of transactions: ${transactions.length}`);
            console.log(`🎯 Detected operation: ${pendingOperationType}`);
            console.log('='.repeat(60));

            transactions.forEach((tx, i) => {
                console.log(`\n--- Transaction ${i + 1} ---`);
                if (tx.version !== undefined || tx.message) {
                    decodeVersionedTransaction(tx, pendingOperationType);
                } else {
                    console.log('Legacy transaction format');
                    console.log(tx);
                }
            });

            pendingOperationType = 'unknown';
            throw new Error('Transactions intercepted for analysis - check console for details');
        };
    }

    // Override signAndSendTransaction (some wallets use this)
    if (originalSignAndSendTransaction) {
        wallet.signAndSendTransaction = async function(transaction, options) {
            console.log('\n' + '='.repeat(60));
            console.log('✍️ INTERCEPTED signAndSendTransaction');
            console.log(`🎯 Detected operation: ${pendingOperationType}`);
            console.log('='.repeat(60));

            if (transaction.version !== undefined || transaction.message) {
                decodeVersionedTransaction(transaction, pendingOperationType);
            } else {
                console.log('Legacy transaction format');
                console.log(transaction);
            }

            pendingOperationType = 'unknown';
            throw new Error('Transaction intercepted for analysis - check console for details');
        };
    }

    console.log('✅ Wallet methods intercepted!');
}

// Helper function to print all discovered discriminators
window.printDiscriminators = function() {
    console.log('\n📊 All Discovered Discriminators:');
    console.log(JSON.stringify(discoveredDiscriminators, null, 2));
    return discoveredDiscriminators;
};

// Helper to manually set operation type before transaction
window.setOperationType = function(type) {
    pendingOperationType = type;
    console.log(`✅ Operation type set to: ${type}`);
};

console.log('');
console.log('✅ Ready! Now try operations on https://samsara.nirvana.finance');
console.log('💡 The transaction will be blocked and logged to console.');
console.log('📝 Look for the "Copyable JSON" section for full transaction details.');
console.log('');
console.log('🔧 Helper commands:');
console.log('   printDiscriminators() - Show all discovered instruction discriminators');
console.log('   setOperationType("buy") - Manually set operation type before transaction');
console.log('');
console.log('🎯 Operations to intercept:');
console.log('   - Buy navSOL/navZEC');
console.log('   - Sell navSOL/navZEC');
console.log('   - Stake navTokens');
console.log('   - Unstake navTokens');
console.log('   - Borrow against staked position');
console.log('   - Repay borrowed position');
console.log('   - Claim rewards');
