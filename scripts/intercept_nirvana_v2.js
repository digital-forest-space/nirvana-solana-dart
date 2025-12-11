// Enhanced browser console script to intercept and decode Nirvana transactions
// Run this in the browser console on https://app.nirvana.finance

console.log('🔍 Nirvana Transaction Interceptor V2 Started');

// Helper to convert Uint8Array to hex string
function uint8ArrayToHex(uint8Array) {
    return Array.from(uint8Array)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}

// Helper to decode versioned transaction
function decodeVersionedTransaction(tx) {
    console.log('📦 Versioned Transaction Detected');
    
    const message = tx.message;
    if (!message) {
        console.log('❌ No message found in transaction');
        return;
    }
    
    // Extract static account keys
    const accounts = message.staticAccountKeys || [];
    console.log(`\n📑 Accounts (${accounts.length} total):`);
    accounts.forEach((acc, i) => {
        console.log(`  ${i}: ${acc.toString()}`);
    });
    
    // Decode compiled instructions
    const instructions = message.compiledInstructions || [];
    console.log(`\n📋 Instructions (${instructions.length} total):`);
    
    instructions.forEach((ix, i) => {
        console.log(`\n🔸 Instruction ${i}:`);
        
        // Program ID is at the programIdIndex
        const programId = accounts[ix.programIdIndex]?.toString();
        console.log(`  Program: ${programId}`);
        
        // Decode account indices
        console.log(`  Accounts (${ix.accountKeyIndexes.length}):`);
        ix.accountKeyIndexes.forEach((accIndex, j) => {
            const pubkey = accounts[accIndex]?.toString();
            console.log(`    ${j}: [${accIndex}] ${pubkey}`);
        });
        
        // Decode instruction data
        const dataHex = uint8ArrayToHex(ix.data);
        console.log(`  Data: ${dataHex}`);
        
        // If Nirvana program, decode discriminator
        if (programId === 'NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb') {
            const discriminator = Array.from(ix.data.slice(0, 8));
            console.log(`  Discriminator: [${discriminator.join(', ')}]`);
            
            // Try to identify instruction
            const discrimStr = discriminator.join(',');
            if (discrimStr === '109,5,199,243,164,233,19,152') {
                console.log('  ✅ Instruction: buy_exact2');
            } else if (discrimStr === '83,31,161,53,165,23,164,72') {
                console.log('  ✅ Instruction: buy2');
            } else {
                console.log('  ❓ Unknown instruction');
            }
            
            // Decode amounts if buy instruction
            if (ix.data.length >= 24) {
                const amount1 = new DataView(ix.data.buffer, ix.data.byteOffset + 8, 8).getBigUint64(0, true);
                const amount2 = new DataView(ix.data.buffer, ix.data.byteOffset + 16, 8).getBigUint64(0, true);
                console.log(`  Amount 1: ${amount1} (${Number(amount1) / 1e6} USDC)`);
                console.log(`  Amount 2: ${amount2}`);
            }
        }
        
        // Check for compute budget instructions
        if (programId === 'ComputeBudget111111111111111111111111111111') {
            if (ix.data[0] === 0) {
                const units = new DataView(ix.data.buffer, ix.data.byteOffset + 1, 4).getUint32(0, true);
                console.log(`  ✅ Set Compute Unit Limit: ${units}`);
            } else if (ix.data[0] === 3) {
                const microLamports = new DataView(ix.data.buffer, ix.data.byteOffset + 1, 8).getBigUint64(0, true);
                console.log(`  ✅ Set Compute Unit Price: ${microLamports} microLamports`);
            }
        }
    });
    
    console.log(`\n🔗 Recent Blockhash: ${message.recentBlockhash}`);
    
    // Create copyable output
    const output = {
        accounts: accounts.map(a => a.toString()),
        instructions: instructions.map((ix, i) => {
            const programId = accounts[ix.programIdIndex]?.toString();
            return {
                index: i,
                programId: programId,
                programIdIndex: ix.programIdIndex,
                accounts: ix.accountKeyIndexes.map(idx => ({
                    index: idx,
                    pubkey: accounts[idx]?.toString()
                })),
                data: uint8ArrayToHex(ix.data),
                discriminator: Array.from(ix.data.slice(0, 8))
            };
        }),
        recentBlockhash: message.recentBlockhash
    };
    
    console.log('\n📋 Copyable JSON:');
    console.log(JSON.stringify(output, null, 2));
    
    // Also create a simple copyable string with key info
    console.log('\n📝 Quick Copy - Accounts for buy_exact2:');
    const buyInstructionIndex = instructions.findIndex(ix => 
        accounts[ix.programIdIndex]?.toString() === 'NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb'
    );
    
    if (buyInstructionIndex >= 0) {
        const buyIx = instructions[buyInstructionIndex];
        console.log('Copy this line:');
        const accountsList = buyIx.accountKeyIndexes.map(idx => accounts[idx]?.toString()).join(',');
        console.log(accountsList);
        
        console.log('\nAccount mapping:');
        buyIx.accountKeyIndexes.forEach((idx, i) => {
            console.log(`${i}: ${accounts[idx]?.toString()}`);
        });
    }
}

// Store original methods
const wallet = window.solana || window.phantom?.solana || window.solflare;
if (!wallet) {
    console.error('❌ No Solana wallet found! Please connect a wallet first.');
} else {
    const originalSignTransaction = wallet.signTransaction;
    const originalSignAllTransactions = wallet.signAllTransactions;
    const originalSendTransaction = wallet.sendTransaction;

    // Override signTransaction
    if (originalSignTransaction) {
        wallet.signTransaction = async function(transaction) {
            console.log('\n✍️ INTERCEPTED signTransaction');
            
            // Check if it's a versioned transaction
            if (transaction.version !== undefined || transaction.message) {
                decodeVersionedTransaction(transaction);
            } else {
                console.log('Legacy transaction format detected');
                decodeTransaction(transaction);
            }
            
            throw new Error('Transaction intercepted for analysis - check console for details');
        };
    }

    // Override signAllTransactions
    if (originalSignAllTransactions) {
        wallet.signAllTransactions = async function(transactions) {
            console.log('\n✍️ INTERCEPTED signAllTransactions');
            console.log(`Number of transactions: ${transactions.length}`);
            
            transactions.forEach((tx, i) => {
                console.log(`\n--- Transaction ${i + 1} ---`);
                if (tx.version !== undefined || tx.message) {
                    decodeVersionedTransaction(tx);
                } else {
                    decodeTransaction(tx);
                }
            });
            
            throw new Error('Transactions intercepted for analysis - check console for details');
        };
    }

    console.log('✅ Wallet methods intercepted!');
}

console.log('✅ Ready! Now try to buy ANA on the website.');
console.log('💡 The transaction will be blocked and logged.');
console.log('📝 Look for the Copyable JSON section to get transaction details.');