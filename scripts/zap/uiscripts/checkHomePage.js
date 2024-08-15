const driver = browser.driver
const EC = protractor.ExpectedConditions;
browser.ignoreSynchronization = true;

const WAIT_ONE_MINUTE = 60 * 1000

afterAll(function () {
    driver.quit();
});

describe('Browse home page to create sites list for zap', function () {

    //browse page without login
    it('Browse page to homepage', function () {
        const Url = `${process.env.APP_URL}/`
        driver.get(Url);
        driver.sleep(10*1000); //wait 10 sec
    }, WAIT_ONE_MINUTE)

}, WAIT_ONE_MINUTE)
