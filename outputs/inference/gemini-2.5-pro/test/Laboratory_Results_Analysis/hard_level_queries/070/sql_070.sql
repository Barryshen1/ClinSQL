with hemorrhagic stroke,
-- compute a 72‑hour lab instability score (count of unique abnormal labs),
-- stratify into quartiles, and report LOS, mortality, and per‑lab abnormal
-- rates versus general inpatients.

WITH
-- Step 1: Find all ICD codes related to hemorrhagic stroke.
icd_codes AS (
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        LOWER(long_title) LIKE '%intracerebral hemorrhage%'
        OR LOWER(long_title) LIKE '%subarachnoid hemorrhage%'
        OR LOWER(long_title) LIKE '%intracranial hemorrhage%'
),

-- Step 2: Identify the target cohort of male patients aged 40-50 with a hemorrhagic stroke diagnosis.
stroke_cohort AS (
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN icd_codes
        ON dx.icd_code = icd_codes.icd_code AND dx.icd_version = icd_codes.icd_version
    WHERE
        pat.gender = 'M'
        -- Calculate age at the time of admission
        AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 40 AND 50
),

-- Step 3: Get all lab events in the first 72 hours for all admissions and flag abnormal ones.
labs_72h AS (
    SELECT
        lab.hadm_id,
        lab.itemid,
        -- Flag is 1 if the lab value is outside the reference range, otherwise 0.
        CASE
            WHEN lab.valuenum IS NOT NULL AND lab.ref_range_lower IS NOT NULL AND lab.ref_range_upper IS NOT NULL
            AND (lab.valuenum < lab.ref_range_lower OR lab.valuenum > lab.ref_range_upper)
            THEN 1
            ELSE 0
        END AS is_abnormal
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS lab
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON lab.hadm_id = adm.hadm_id
    WHERE
        -- Filter labs to the first 72 hours of admission.
        lab.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
        AND lab.valuenum IS NOT NULL
),

-- Step 4: For each patient, calculate the instability score and the total number of unique labs measured.
patient_lab_scores AS (
    SELECT
        hadm_id,
        -- Lab Instability Score: Count of unique labs that were abnormal at least once.
        COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN itemid END) AS lab_instability_score,
        -- Total unique labs measured for the patient in the time window.
        COUNT(DISTINCT itemid) AS total_unique_labs_measured
    FROM labs_72h
    GROUP BY hadm_id
),

-- Step 5: Create a base table for analysis, combining cohort info, scores, LOS, and mortality.
analysis_base AS (
    SELECT
        adm.hadm_id,
        CASE
            WHEN sc.hadm_id IS NOT NULL THEN 'Hemorrhagic Stroke 40-50 M'
            ELSE 'General Inpatient'
        END AS cohort,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        COALESCE(pls.lab_instability_score, 0) AS lab_instability_score,
        COALESCE(pls.total_unique_labs_measured, 0) AS total_unique_labs_measured
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    LEFT JOIN stroke_cohort AS sc
        ON adm.hadm_id = sc.hadm_id
    LEFT JOIN patient_lab_scores AS pls
        ON adm.hadm_id = pls.hadm_id
),

-- Step 6: Stratify the stroke cohort into quartiles based on their instability score.
stroke_quartiles AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY lab_instability_score) AS score_quartile
    FROM analysis_base
    WHERE cohort = 'Hemorrhagic Stroke 40-50 M'
),

-- Step 7a: Calculate final metrics for the stroke cohort, grouped by quartile.
stroke_results AS (
    SELECT
        CAST(CONCAT('Stroke Cohort - Quartile ', score_quartile) AS STRING) AS stratum,
        COUNT(hadm_id) AS num_patients,
        MIN(lab_instability_score) AS min_score,
        MAX(lab_instability_score) AS max_score,
        AVG(los) AS avg_los_days,
        AVG(hospital_expire_flag) AS mortality_rate,
        -- Per-lab abnormal rate: average number of unique abnormal labs / average number of unique labs tested.
        SAFE_DIVIDE(AVG(lab_instability_score), AVG(total_unique_labs_measured)) AS per_lab_abnormal_rate
    FROM stroke_quartiles
    GROUP BY score_quartile
),

-- Step 7b: Calculate final metrics for the general inpatient population as a baseline.
general_results AS (
    SELECT
        cohort AS stratum,
        COUNT(hadm_id) AS num_patients,
        NULL AS min_score,
        NULL AS max_score,
        AVG(los) AS avg_los_days,
        AVG(hospital_expire_flag) AS mortality_rate,
        SAFE_DIVIDE(AVG(lab_instability_score), AVG(total_unique_labs_measured)) AS per_lab_abnormal_rate
    FROM analysis_base
    WHERE cohort = 'General Inpatient'
    GROUP BY cohort
)

-- Step 8: Combine the results from the stroke quartiles and the general population.
SELECT * FROM stroke_results
UNION ALL
SELECT * FROM general_results
ORDER BY
    CASE
        WHEN stratum LIKE 'Stroke%' THEN 1
        ELSE 2
    END,
    stratum;