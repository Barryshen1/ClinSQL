WITH cohort_admissions AS (
    -- Select initial cohort: female, age 45-55, inpatient admission types
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        pa.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 45 AND 55
        AND ad.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE', 'DIRECT EMER', 'DIRECT TRAUMA')
),
multi_trauma_cohort AS (
    -- Further filter for multi-trauma diagnosis (ICD-10 code T07 for Unspecified multiple injuries)
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.deathtime,
        ca.hospital_expire_flag,
        ca.anchor_age
    FROM
        cohort_admissions AS ca
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ca.hadm_id = di.hadm_id
    WHERE
        di.icd_version = 10 AND di.icd_code = 'T07'
    GROUP BY -- Ensure each HADM_ID is only counted once for diagnosis
        ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.deathtime, ca.hospital_expire_flag, ca.anchor_age
),
medication_complexity_calc AS (
    -- Calculate medication complexity: count distinct drugs in the first 7 days of admission
    SELECT
        mtc.subject_id,
        mtc.hadm_id,
        COUNT(DISTINCT p.drug) AS med_complexity_score
    FROM
        multi_trauma_cohort AS mtc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
        ON mtc.subject_id = p.subject_id AND mtc.hadm_id = p.hadm_id
    WHERE
        p.starttime BETWEEN mtc.admittime AND DATE_ADD(mtc.admittime, INTERVAL 7 DAY)
    GROUP BY
        mtc.subject_id, mtc.hadm_id
),
admission_details AS (
    -- Combine cohort admissions with their calculated medication complexity and LOS
    SELECT
        mtc.subject_id,
        mtc.hadm_id,
        mtc.admittime,
        mtc.dischtime,
        mtc.hospital_expire_flag,
        COALESCE(mcc.med_complexity_score, 0) AS med_complexity_score, -- Set 0 if no meds in 7 days
        DATE_DIFF(mtc.dischtime, mtc.admittime, DAY) AS los_days
    FROM
        multi_trauma_cohort AS mtc
    LEFT JOIN
        medication_complexity_calc AS mcc
        ON mtc.hadm_id = mcc.hadm_id
    WHERE
        mtc.dischtime IS NOT NULL -- Exclude ongoing admissions without a recorded discharge
        AND DATE_DIFF(mtc.dischtime, mtc.admittime, DAY) >= 0 -- Ensure valid LOS (discharge after or same day as admission)
),
readmission_status AS (
    -- Identify the next admission for each patient to calculate 30-day readmission
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        ad.med_complexity_score,
        ad.los_days,
        LEAD(ad.admittime) OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime) AS next_admittime
    FROM
        admission_details AS ad
),
final_admissions_with_metrics AS (
    -- Compile all metrics including the 30-day readmission flag
    SELECT
        rs.subject_id,
        rs.hadm_id,
        rs.med_complexity_score,
        rs.los_days,
        rs.hospital_expire_flag,
        CASE
            WHEN rs.hospital_expire_flag = 0  -- Patient was discharged alive
            AND rs.dischtime IS NOT NULL AND rs.next_admittime IS NOT NULL
            AND DATE_DIFF(rs.next_admittime, rs.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmission_30_day_flag
    FROM
        readmission_status AS rs
),
tertile_assignment AS (
    -- Assign each admission to a tertile based on medication complexity score
    SELECT
        *,
        NTILE(3) OVER (ORDER BY med_complexity_score) AS med_complexity_tertile
    FROM
        final_admissions_with_metrics
)
-- Final aggregation to report metrics per tertile
SELECT
    med_complexity_tertile,
    COUNT(hadm_id) AS num_admissions,
    ROUND(AVG(med_complexity_score), 2) AS mean_med_complexity_score,
    MIN(med_complexity_score) AS min_med_complexity_score,
    MAX(med_complexity_score) AS max_med_complexity_score,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id), 2) AS mortality_percent,
    ROUND(SUM(readmission_30_day_flag) * 100.0 / COUNT(hadm_id), 2) AS readmission_30_day_percent
FROM
    tertile_assignment
GROUP BY
    med_complexity_tertile
ORDER BY
    med_complexity_tertile;