WITH AdmissionsCohort AS (
    -- Select admissions for female patients aged 68-78 with ACS diagnosis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 68 AND 78
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND di.icd_version = 10 -- Focusing on ICD-10 for modern ACS definitions
                AND (
                    di.icd_code = 'I200' -- Unstable angina
                    OR di.icd_code LIKE 'I21%' -- Acute myocardial infarction
                    OR di.icd_code LIKE 'I22%' -- Subsequent myocardial infarction
                )
        )
),
FirstTroponinI AS (
    -- Find the first Troponin I measurement for each eligible admission
    SELECT
        ac.subject_id,
        ac.hadm_id,
        le.valuenum AS first_troponin_i_value
    FROM
        AdmissionsCohort ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ac.subject_id = le.subject_id
        AND ac.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50911 -- itemid for Troponin I
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 7 DAY) -- Consider measurements within 7 days of admission for 'initial'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
)
-- Aggregate results for the specified cohort
SELECT
    COUNT(DISTINCT fti.subject_id) AS patient_count,
    COUNT(DISTINCT fti.hadm_id) AS admission_count,
    AVG(fti.first_troponin_i_value) AS mean_initial_troponin_i,
    STDDEV(fti.first_troponin_i_value) AS stddev_initial_troponin_i,
    MIN(fti.first_troponin_i_value) AS min_initial_troponin_i,
    MAX(fti.first_troponin_i_value) AS max_initial_troponin_i
FROM
    FirstTroponinI fti
WHERE
    fti.first_troponin_i_value > 0.04; -- Initial Troponin I exceeded 0.04 ng/mL;