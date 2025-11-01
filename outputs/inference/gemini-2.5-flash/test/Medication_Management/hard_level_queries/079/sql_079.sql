WITH cohort_admissions AS (
    -- Step 1: Identify the initial cohort of male patients aged 89-99 with hemorrhagic stroke
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 89 AND 99
        -- Ensure at least one diagnosis of hemorrhagic stroke (ICD-10 codes I60, I61, I62)
        AND EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
             WHERE di.subject_id = ad.subject_id
               AND di.hadm_id = ad.hadm_id
               AND di.icd_version = 10 -- Assuming ICD-10 for I60-I62
               AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')
        )
),
med_complexity AS (
    -- Step 2: Calculate unique drugs administered in the first 7 days for the cohort admissions
    SELECT
        ca.subject_id,
        ca.hadm_id,
        COUNT(DISTINCT ph.medication) AS unique_drugs_first_7_days
    FROM
        cohort_admissions ca
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
        ON ca.subject_id = ph.subject_id
        AND ca.hadm_id = ph.hadm_id
    WHERE
        ph.starttime IS NOT NULL -- Exclude records without a starttime
        AND ph.starttime >= ca.admittime
        AND ph.starttime < DATETIME_ADD(ca.admittime, INTERVAL 7 DAY)
    GROUP BY
        ca.subject_id, ca.hadm_id
),
-- Step 3a: Get the next admission time for each visit across all patient admissions
all_admissions_with_next AS (
    SELECT
        subject_id,
        hadm_id,
        dischtime,
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime_for_patient
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),
readmission_flagged AS (
    -- Step 3b: Flag 30-day readmissions for the cohort admissions
    SELECT
        ca.subject_id,
        ca.hadm_id,
        CASE
            WHEN aawn.next_admittime_for_patient IS NOT NULL
                 AND DATETIME_DIFF(aawn.next_admittime_for_patient, ca.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmission_30_day_flag
    FROM
        cohort_admissions ca
    LEFT JOIN
        all_admissions_with_next aawn
        ON ca.subject_id = aawn.subject_id
        AND ca.hadm_id = aawn.hadm_id
),
final_cohort_metrics AS (
    -- Step 4: Combine all calculated metrics
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.los_days,
        ca.hospital_expire_flag,
        COALESCE(mc.unique_drugs_first_7_days, 0) AS unique_drugs_first_7_days, -- Default to 0 if no drugs in first 7 days
        COALESCE(rf.readmission_30_day_flag, 0) AS readmission_30_day_flag -- Default to 0 if no readmission within 30 days
    FROM
        cohort_admissions ca
    LEFT JOIN
        med_complexity mc
        ON ca.subject_id = mc.subject_id
        AND ca.hadm_id = mc.hadm_id
    LEFT JOIN
        readmission_flagged rf
        ON ca.subject_id = rf.subject_id
        AND ca.hadm_id = rf.hadm_id
),
cohort_with_quintiles AS (
    -- Step 5: Assign medication complexity quintiles
    SELECT
        *,
        NTILE(5) OVER (ORDER BY unique_drugs_first_7_days) AS medication_complexity_quintile
    FROM
        final_cohort_metrics
)
-- Step 6: Aggregate metrics by medication complexity quintile
SELECT
    medication_complexity_quintile,
    AVG(los_days) AS average_los_days,
    AVG(hospital_expire_flag) AS inpatient_mortality_rate, -- AVG of 0/1 flag gives the rate
    AVG(readmission_30_day_flag) AS readmission_30_day_rate -- AVG of 0/1 flag gives the rate
FROM
    cohort_with_quintiles
GROUP BY
    medication_complexity_quintile
ORDER BY
    medication_complexity_quintile;