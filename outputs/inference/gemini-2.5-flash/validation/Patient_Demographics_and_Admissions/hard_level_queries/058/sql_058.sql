WITH initial_cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
        ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 50 AND 60
        AND adm.insurance = 'Medicare'
        AND adm.admission_location = 'EMERGENCY ROOM'
        AND diag.seq_num = 1 -- Principal diagnosis
        -- Filter for 'Lower GI bleeding' based on long_title
        AND (
            LOWER(dicd.long_title) LIKE '%lower gastrointestinal hemorrhage%'
            OR LOWER(dicd.long_title) LIKE '%rectal hemorrhage%'
            OR LOWER(dicd.long_title) LIKE '%hemorrhage of anus and rectum%'
        )
),
readmission_status_cte AS (
    SELECT
        ica.subject_id,
        ica.hadm_id,
        ica.los_days,
        -- Determine if the index admission is followed by a readmission within 30 days
        (
            SELECT COUNT(subsequent_adm.hadm_id)
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS subsequent_adm
            WHERE ica.subject_id = subsequent_adm.subject_id
              AND subsequent_adm.admittime > ica.dischtime -- Subsequent admission must be after current discharge
              AND DATETIME_DIFF(subsequent_adm.admittime, ica.dischtime, DAY) <= 30
              AND ica.hadm_id != subsequent_adm.hadm_id -- Ensure it's a different admission
              AND subsequent_adm.hospital_expire_flag = 0 -- Subsequent admission must also be discharged alive to be a valid readmission
        ) > 0 AS is_readmitted_30_day
    FROM
        initial_cohort_admissions AS ica
    WHERE
        ica.hospital_expire_flag = 0 -- Only consider admissions where the patient was discharged alive as index admissions for readmission tracking
)
SELECT
    -- Overall 30-day readmission rate
    COALESCE(SAFE_DIVIDE(
        COUNTIF(rs.is_readmitted_30_day = TRUE) * 100.0,
        COUNT(rs.hadm_id)
    ), 0.0) AS readmission_rate_30_day_pct,

    -- Median LOS for readmitted patients
    PERCENTILE_CONT(CASE WHEN rs.is_readmitted_30_day = TRUE THEN rs.los_days ELSE NULL END, 0.5) AS median_los_readmitted,

    -- Median LOS for not readmitted patients
    PERCENTILE_CONT(CASE WHEN rs.is_readmitted_30_day = FALSE THEN rs.los_days ELSE NULL END, 0.5) AS median_los_not_readmitted,

    -- Percentage of readmitted patients with LOS > 6 days
    COALESCE(SAFE_DIVIDE(
        COUNTIF(rs.is_readmitted_30_day = TRUE AND rs.los_days > 6) * 100.0,
        COUNTIF(rs.is_readmitted_30_day = TRUE)
    ), 0.0) AS pct_los_gt_6_readmitted_pct,

    -- Percentage of not readmitted patients with LOS > 6 days
    COALESCE(SAFE_DIVIDE(
        COUNTIF(rs.is_readmitted_30_day = FALSE AND rs.los_days > 6) * 100.0,
        COUNTIF(rs.is_readmitted_30_day = FALSE)
    ), 0.0) AS pct_los_gt_6_not_readmitted_pct
FROM
    readmission_status_cte AS rs;