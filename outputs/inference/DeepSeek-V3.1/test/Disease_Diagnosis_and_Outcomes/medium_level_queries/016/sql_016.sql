WITH ami_patients AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) <= 5 THEN 'LOS ≤5'
             ELSE 'LOS >5' END AS los_group,
        p.anchor_age,
        p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
    -- Identify AMI admissions
    AND adm.hadm_id IN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
            ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
        WHERE d.long_title LIKE 'Acute myocardial infarction%'
    )
    -- Exclude admissions with shock or respiratory failure
    AND adm.hadm_id NOT IN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
            ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
        WHERE d.long_title LIKE '%shock%' 
           OR d.long_title LIKE '%respiratory failure%'
    )
),
day1_icu AS (
    SELECT 
        ami.subject_id,
        ami.hadm_id,
        MAX(CASE WHEN DATETIME_DIFF(icu.intime, ami.admittime, HOUR) <= 24 THEN 1 ELSE 0 END) AS in_icu_day1
    FROM ami_patients ami
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ami.hadm_id = icu.hadm_id
    GROUP BY ami.subject_id, ami.hadm_id
)
SELECT 
    los_group,
    CASE WHEN in_icu_day1 = 1 THEN 'ICU day1' ELSE 'No ICU day1' END AS icu_status,
    COUNT(*) AS num_admissions,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
FROM ami_patients ami
INNER JOIN day1_icu icu
    ON ami.hadm_id = icu.hadm_id
GROUP BY los_group, in_icu_day1
ORDER BY los_group, in_icu_day1;