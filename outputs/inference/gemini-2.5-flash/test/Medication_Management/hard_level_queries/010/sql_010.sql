WITH cohort_admissions AS (
    -- Select initial cohort based on demographics: male, age 61-71
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 61 AND 71
),
hemorrhagic_stroke_admissions AS (
    -- Further filter cohort for hemorrhagic stroke diagnosis (ICD-10 I60.x or I61.x)
    SELECT DISTINCT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.deathtime,
        ca.hospital_expire_flag
    FROM cohort_admissions ca
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ca.subject_id = diag.subject_id AND ca.hadm_id = diag.hadm_id
    WHERE
        diag.icd_version = 10
        AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%')
),
med_complexity AS (
    -- Calculate first-24-hour medication complexity score (distinct drugs)
    SELECT
        hsa.subject_id,
        hsa.hadm_id,
        COUNT(DISTINCT pres.drug) AS med_complexity_score
    FROM hemorrhagic_stroke_admissions hsa
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
        ON hsa.subject_id = pres.subject_id AND hsa.hadm_id = pres.hadm_id
    WHERE
        pres.starttime >= hsa.admittime
        AND pres.starttime <= TIMESTAMP_ADD(hsa.admittime, INTERVAL 24 HOUR)
    GROUP BY hsa.subject_id, hsa.hadm_id
),
cohort_with_med_score AS (
    -- Combine hemorrhagic stroke admissions with their medication complexity score
    -- Use COALESCE to handle admissions with no medications in the first 24 hours
    SELECT
        hsa.subject_id,
        hsa.hadm_id,
        hsa.admittime,
        hsa.dischtime,
        hsa.deathtime,
        hsa.hospital_expire_flag,
        COALESCE(mc.med_complexity_score, 0) AS med_complexity_score
    FROM hemorrhagic_stroke_admissions hsa
    LEFT JOIN med_complexity mc
        ON hsa.subject_id = mc.subject_id AND hsa.hadm_id = mc.hadm_id
),
cohort_with_readmission_status AS (
    -- Determine 30-day readmission status for each admission in the cohort
    SELECT
        cwm.subject_id,
        cwm.hadm_id,
        cwm.admittime,
        cwm.dischtime,
        cwm.deathtime,
        cwm.hospital_expire_flag,
        cwm.med_complexity_score,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm_sub
                WHERE adm_sub.subject_id = cwm.subject_id
                AND adm_sub.hadm_id != cwm.hadm_id -- Exclude the current admission itself
                AND adm_sub.admittime BETWEEN cwm.dischtime AND TIMESTAMP_ADD(cwm.dischtime, INTERVAL 30 DAY)
            ) THEN 1
            ELSE 0
        END AS readmit_30_day_flag
    FROM cohort_with_med_score cwm
),
cohort_with_quintile AS (
    -- Assign each admission to a medication complexity quintile
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        deathtime,
        hospital_expire_flag,
        med_complexity_score,
        readmit_30_day_flag,
        NTILE(5) OVER (ORDER BY med_complexity_score ASC) AS medication_complexity_quintile
    FROM cohort_with_readmission_status
)
-- Final aggregation to calculate metrics per quintile
SELECT
    medication_complexity_quintile,
    COUNT(DISTINCT hadm_id) AS number_of_patients,
    AVG(med_complexity_score) AS mean_complexity_score,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS average_los_days,
    SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id) AS in_hospital_mortality_rate,
    SUM(readmit_30_day_flag) * 100.0 / COUNT(DISTINCT hadm_id) AS readmission_30_day_rate
FROM cohort_with_quintile
GROUP BY medication_complexity_quintile
ORDER BY medication_complexity_quintile;