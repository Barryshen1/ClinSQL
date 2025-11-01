WITH cohort_base AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 87 AND 97
        AND EXISTS ( -- Filter for Intracranial Hemorrhage (ICH) diagnoses
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE adm.hadm_id = di.hadm_id
            AND di.icd_version IN (9, 10)
            AND (
                (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%')) -- ICD-9 for ICH
                OR
                (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')) -- ICD-10 for ICH
            )
        )
),
med_complexity_raw AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        COUNT(DISTINCT p.drug || '-' || COALESCE(p.route, 'NO_ROUTE')) AS med_complexity_score
    FROM
        cohort_base cb
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON cb.subject_id = p.subject_id AND cb.hadm_id = p.hadm_id
    WHERE
        p.starttime >= cb.admittime
        AND p.starttime <= TIMESTAMP_ADD(cb.admittime, INTERVAL 48 HOUR) -- Prescriptions in first 48 hours
    GROUP BY
        cb.subject_id, cb.hadm_id
),
readmission_status AS (
    -- Get next admission time for all admissions to calculate 30-day readmission
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.dischtime,
        LEAD(adm.admittime) OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
),
readmission_30d AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        CASE
            WHEN rs.next_admittime IS NOT NULL
             AND TIMESTAMP_DIFF(rs.next_admittime, rs.dischtime, DAY) <= 30 THEN 1
            ELSE 0
        END AS readmission_30_day_flag
    FROM
        cohort_base cb
    LEFT JOIN
        readmission_status rs
        ON cb.subject_id = rs.subject_id AND cb.hadm_id = rs.hadm_id
),
final_cohort_metrics AS (
    SELECT
        cb.subject_id,
        cb.hadm_id,
        COALESCE(mc.med_complexity_score, 0) AS med_complexity_score, -- assign 0 if no prescriptions found
        TIMESTAMP_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0 AS los_days,
        cb.hospital_expire_flag AS mortality_flag,
        r30.readmission_30_day_flag
    FROM
        cohort_base cb
    LEFT JOIN                               -- Use LEFT JOIN to include admissions with 0 complexity
        med_complexity_raw mc
        ON cb.subject_id = mc.subject_id AND cb.hadm_id = mc.hadm_id
    LEFT JOIN                               -- Changed from INNER JOIN to LEFT JOIN to ensure all cohort_base admissions are included
        readmission_30d r30
        ON cb.subject_id = r30.subject_id AND cb.hadm_id = r30.hadm_id
),
cohort_with_quartile AS (
    SELECT
        subject_id,
        hadm_id,
        med_complexity_score,
        los_days,
        mortality_flag,
        readmission_30_day_flag,
        NTILE(4) OVER (ORDER BY med_complexity_score ASC) AS complexity_quartile
    FROM
        final_cohort_metrics
)
SELECT
    complexity_quartile,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    MIN(med_complexity_score) AS min_complexity_score,
    MAX(med_complexity_score) AS max_complexity_score,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(mortality_flag) * 100, 2) AS mortality_percentage,
    ROUND(AVG(readmission_30_day_flag) * 100, 2) AS readmission_30_day_percentage
FROM
    cohort_with_quartile
GROUP BY
    complexity_quartile
ORDER BY
    complexity_quartile;