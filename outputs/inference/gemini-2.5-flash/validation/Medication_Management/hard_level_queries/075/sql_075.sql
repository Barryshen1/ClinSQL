WITH TargetAdmissions AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_on_admission, -- Calculate age at the time of admission
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 58 AND 68 -- Filter by calculated age
        AND di.seq_num = 1 -- Principal diagnosis of admission
        AND (
                (di.icd_version = 9 AND di.icd_code = '49121') -- Chronic obstructive bronchitis with acute exacerbation (ICD-9)
             OR (di.icd_version = 10 AND di.icd_code = 'J441') -- Chronic obstructive pulmonary disease with acute exacerbation (ICD-10)
            )
),
MedicationComplexity AS (
    SELECT
        ta.subject_id,
        ta.hadm_id,
        ta.admittime,
        ta.dischtime,
        ta.hospital_expire_flag,
        COALESCE(COUNT(DISTINCT p.drug), 0) AS medication_complexity_score -- Count distinct drugs within first 72 hours
    FROM
        TargetAdmissions ta
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON ta.subject_id = p.subject_id
        AND ta.hadm_id = p.hadm_id
        AND p.starttime >= ta.admittime
        AND p.starttime < DATETIME_ADD(ta.admittime, INTERVAL '72' HOUR) -- Corrected INTERVAL syntax for BigQuery DATETIME_ADD
    GROUP BY
        ta.subject_id,
        ta.hadm_id,
        ta.admittime,
        ta.dischtime,
        ta.hospital_expire_flag
),
AllAdmissionsRanked AS (
    -- Get next admission time for each patient to determine 30-day readmission status
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),
AdmissionsWithMetrics AS (
    SELECT
        mc.subject_id,
        mc.hadm_id,
        mc.medication_complexity_score,
        DATETIME_DIFF(mc.dischtime, mc.admittime, HOUR) / 24.0 AS los_days, -- Length of Stay in days
        mc.hospital_expire_flag,
        CASE
            WHEN aar.next_admittime IS NOT NULL AND aar.next_admittime BETWEEN mc.dischtime AND DATETIME_ADD(mc.dischtime, INTERVAL '30' DAY) THEN 1 -- Corrected INTERVAL syntax
            ELSE 0
        END AS thirty_day_readmission_flag -- Flag for 30-day readmission
    FROM
        MedicationComplexity mc
    INNER JOIN
        AllAdmissionsRanked aar
        ON mc.subject_id = aar.subject_id
        AND mc.hadm_id = aar.hadm_id
),
AdmissionsWithTertile AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY medication_complexity_score ASC) AS complexity_tertile
    FROM
        AdmissionsWithMetrics
)
SELECT
    complexity_tertile,
    COUNT(hadm_id) AS n_admissions,
    MIN(medication_complexity_score) AS min_complexity_score,
    MAX(medication_complexity_score) AS max_complexity_score,
    AVG(medication_complexity_score) AS mean_complexity_score,
    AVG(los_days) AS mean_los_days,
    SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id) AS mortality_percent,
    SUM(thirty_day_readmission_flag) * 100.0 / COUNT(hadm_id) AS thirty_day_readmission_percent
FROM
    AdmissionsWithTertile
GROUP BY
    complexity_tertile
ORDER BY
    complexity_tertile;