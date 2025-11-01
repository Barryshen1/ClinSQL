WITH cohort_admissions AS (
    -- Step 1: Identify female patients aged 53-63 at hospital admission
    SELECT
        pa.subject_id,
        ad.hadm_id,
        (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 53 AND 63
),
admissions_in_stepdown_imc AS (
    -- Step 2: Filter for admissions where the patient was ever in a 'step-down' or 'IMC' care unit
    SELECT DISTINCT
        ca.subject_id,
        ca.hadm_id
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.transfers` tr
        ON ca.subject_id = tr.subject_id AND ca.hadm_id = tr.hadm_id
    WHERE
        -- Using UPPER() for case-insensitive matching due to varying capitalization in careunit names
        UPPER(tr.careunit) LIKE '%IMC%' OR UPPER(tr.careunit) LIKE '%STEP%DOWN%'
),
eligible_icu_stays AS (
    -- Step 3: Link these admissions to their ICU stays, getting stay_id and stay times
    SELECT DISTINCT
        asdi.subject_id,
        asdi.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime
    FROM
        admissions_in_stepdown_imc asdi
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON asdi.subject_id = icu.subject_id AND asdi.hadm_id = icu.hadm_id
),
vent_patients_icu_stays AS (
    -- Step 4: Identify ICU stays where invasive mechanical ventilation occurred
    SELECT DISTINCT
        eis.stay_id
    FROM
        eligible_icu_stays eis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON eis.subject_id = ce.subject_id
        AND eis.hadm_id = ce.hadm_id
        AND eis.stay_id = ce.stay_id
    WHERE
        -- ItemID 227362 for 'Invasive Ventilation' with 'Set' value indicates active ventilation
        ce.itemid = 227362 AND LOWER(ce.value) = 'set'
        -- Ensure the ventilation event charttime falls within the ICU stay duration
        AND ce.charttime BETWEEN eis.intime AND eis.outtime
),
nighttime_sbp_measurements AS (
    -- Step 5: Extract SBP measurements for the identified ICU stays, filtered by nighttime and unit
    SELECT
        ce.valuenum
    FROM
        vent_patients_icu_stays vpis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON vpis.stay_id = ce.stay_id
    WHERE
        -- ItemIDs for Systolic Blood Pressure (Arterial and Non-Invasive)
        ce.itemid IN (220050, 220179) 
        AND ce.valuenum IS NOT NULL
        AND ce.valueuom = 'mmHg'
        -- Filter for nighttime hours (00:00 to before 06:00)
        AND EXTRACT(HOUR FROM ce.charttime) >= 0
        AND EXTRACT(HOUR FROM ce.charttime) < 6
)
-- Step 6: Calculate the standard deviation of these SBP measurements
SELECT
    STDDEV(valuenum) AS nighttime_sbp_stddev_mmHg
FROM
    nighttime_sbp_measurements;