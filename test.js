const scraper = require('./scraper');

async function runTests() {
  console.log('--- 1. Testing getLatest() ---');
  const latest = await scraper.getLatest(1);
  console.log(`Tìm thấy ${latest.length} phim mới:`);
  if (latest.length > 0) {
    console.log('Ví dụ phim đầu tiên:', latest[0]);
  }

  console.log('\n--- 2. Testing search("PRED-534") ---');
  const searchResults = await scraper.search('PRED-534');
  console.log(`Tìm thấy ${searchResults.length} kết quả:`);
  if (searchResults.length > 0) {
    console.log('Kết quả:', searchResults[0]);
  }

  const testId = searchResults.length > 0 ? searchResults[0].rawId : (latest.length > 0 ? latest[0].rawId : '3219');

  console.log(`\n--- 3. Testing getVideoDetails("${testId}") ---`);
  const details = await scraper.getVideoDetails(testId);
  console.log('Thông tin chi tiết:', details);

  console.log(`\n--- 4. Testing getStreams("${testId}") ---`);
  const streams = await scraper.getStreams(testId);
  console.log(`Tìm thấy ${streams.length} stream server:`);
  console.log(JSON.stringify(streams, null, 2));

  console.log('\n✅ All tests completed!');
}

runTests().catch(console.error);
