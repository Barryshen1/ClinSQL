WITH patient_cohort AS (
    -- Step 1: Identify female patients aged 36-46 at admission
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 36 AND 46
),
ischemic_admissions AS (
    -- Step 2: Filter for admissions with a diagnosis of ischemic heart disease
    SELECT DISTINCT
        pc.hadm_id
    FROM
        patient_cohort AS pc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON pc.hadm_id = dx.hadm_id
    WHERE
        -- ICD-9 codes for Ischemic Heart Diseases (410-414)
        (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) IN ('410', '411', '412', '413', '414'))
        -- ICD-10 codes for Ischemic Heart Diseases (I20-I25)
        OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('I20', 'I21', 'I22', 'I23', 'I24', 'I25'))
),
initial_troponin AS (
    -- Step 3: Find the first high-sensitivity Troponin T measurement for each admission
    SELECT
        ia.hadm_id,
        le.valuenum,
        le.ref_range_upper,
        ROW_NUMBER() OVER(PARTITION BY ia.hadm_id ORDER BY le.charttime) AS rn
    FROM
        ischemic_admissions AS ia
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ia.hadm_id = le.hadm_id
    WHERE
        le.itemid = 52598 -- Troponin T, High Sensitivity
        AND le.valuenum IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
)
-- Step 4: Filter for initial values > ULN and calculate statistics
SELECT
    APPROX_QUANTILES(it.valuenum, 100)[OFFSET(25)] AS troponin_t_p25,
    APPROX_QUANTILES(it.valuenum, 100)[OFFSET(50)] AS troponin_t_p50,
    APPROX_QUANTILES(it.valuenum, 100)[OFFSET(75)] AS troponin_t_p75,
    MIN(it.valuenum) AS troponin_t_min,
    MAX(it.valuenum) AS troponin_t_max
FROM
    initial_troponin AS it
WHERE
    it.rn = 1  -- Only the first measurement
    AND it.valuenum > it.ref_range_upper; -- Only values above the upper limit of normal;