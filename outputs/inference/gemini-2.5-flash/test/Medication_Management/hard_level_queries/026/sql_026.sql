WITH pneumonia_admissions AS (
    -- Step 1: Identify the target patient cohort (female, 76-86, with pneumonia)
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 76 AND 86
        AND (
            (di.icd_version = 9 AND di.icd_code BETWEEN '480' AND '48699') -- ICD-9 pneumonia codes
            OR (di.icd_version = 10 AND di.icd_code BETWEEN 'J12' AND 'J189') -- ICD-10 pneumonia codes
        )
),
medication_complexity AS (
    -- Step 2: Calculate medication complexity (unique drugs in first 7 days) and LOS
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        pa.deathtime,
        pa.hospital_expire_flag,
        COUNT(DISTINCT pr.drug) AS unique_drugs_7d_score,
        DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days
    FROM
        pneumonia_admissions AS pa
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        ON pa.subject_id = pr.subject_id
        AND pa.hadm_id = pr.hadm_id
        -- Drugs administered within the first 7 days of admission
        AND pr.starttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 7 DAY)
    GROUP BY
        pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.deathtime, pa.hospital_expire_flag
),
admissions_with_readmission_flag AS (
    -- Step 3: Determine 30-day readmission status for each admission
    SELECT
        mc.*,
        -- Get the admission time of the next admission for the same patient
        LEAD(mc.admittime) OVER (PARTITION BY mc.subject_id ORDER BY mc.admittime) AS next_admittime,
        -- Flag for readmission within 30 days of discharge
        CASE
            WHEN DATETIME_DIFF(LEAD(mc.admittime) OVER (PARTITION BY mc.subject_id ORDER BY mc.admittime), mc.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmission_30_day
    FROM
        medication_complexity AS mc
),
admissions_with_tertile AS (
    -- Step 4: Assign medication complexity tertiles
    SELECT
        *,
        NTILE(3) OVER (ORDER BY unique_drugs_7d_score) AS med_complexity_tertile
    FROM
        admissions_with_readmission_flag
)
-- Step 5: Aggregate results by medication complexity tertile
SELECT
    med_complexity_tertile,
    COUNT(hadm_id) AS admissions_count,
    MIN(unique_drugs_7d_score) AS min_unique_drugs_score,
    AVG(unique_drugs_7d_score) AS avg_unique_drugs_score,
    MAX(unique_drugs_7d_score) AS max_unique_drugs_score,
    AVG(los_days) AS mean_los_days,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id) AS in_hospital_mortality_percent,
    SUM(readmission_30_day) * 100.0 / COUNT(hadm_id) AS readmission_30_day_percent
FROM
    admissions_with_tertile
GROUP BY
    med_complexity_tertile
ORDER BY
    med_complexity_tertile;