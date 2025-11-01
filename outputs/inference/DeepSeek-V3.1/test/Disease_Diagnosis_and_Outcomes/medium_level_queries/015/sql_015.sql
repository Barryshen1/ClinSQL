WITH stroke_cohort AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        COUNT(DISTINCT diag.icd_code) AS n_icd_codes
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 48 AND 58
        AND (d.long_title LIKE '%stroke%' 
             OR d.long_title LIKE '%cerebrovascular accident%'
             OR d.long_title LIKE '%CVA%'
             OR d.long_title LIKE '%infarct%'
             OR d.long_title LIKE '%hemorrhage%'
             OR d.long_title LIKE '%haemorrhage%'
             OR d.icd_code LIKE 'I60%'
             OR d.icd_code LIKE 'I61%'
             OR d.icd_code LIKE 'I62%'
             OR d.icd_code LIKE 'I63%'
             OR d.icd_code LIKE 'I64%'
             OR d.icd_code LIKE 'I65%'
             OR d.icd_code LIKE 'I66%'
             OR d.icd_code LIKE 'I67%'
             OR d.icd_code LIKE 'I68%'
             OR d.icd_code LIKE 'I69%'
             OR d.icd_code LIKE 'G45%'
             OR d.icd_code LIKE 'G46%'
             OR d.icd_code LIKE '430%'
             OR d.icd_code LIKE '431%'
             OR d.icd_code LIKE '432%'
             OR d.icd_code LIKE '433%'
             OR d.icd_code LIKE '434%'
             OR d.icd_code LIKE '435%'
             OR d.icd_code LIKE '436%'
             OR d.icd_code LIKE '437%'
             OR d.icd_code LIKE '438%')
    GROUP BY adm.subject_id, adm.hadm_id, adm.hospital_expire_flag, los_days
),

icu_status AS (
    SELECT
        hadm_id,
        MAX(CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_admission
    FROM stroke_cohort
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        USING (hadm_id)
    GROUP BY hadm_id
),

comorbidity_median AS (
    SELECT
        APPROX_QUANTILES(n_icd_codes, 2)[OFFSET(1)] AS median_icd_count
    FROM stroke_cohort
)

SELECT
    CASE WHEN icu.icu_admission = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    CASE WHEN sc.los_days <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
    CASE WHEN sc.n_icd_codes <= (SELECT median_icd_count FROM comorbidity_median) 
         THEN 'Low Comorbidity' ELSE 'High Comorbidity' END AS comorbidity_group,
    COUNT(*) AS n_admissions,
    SUM(sc.hospital_expire_flag) AS n_deaths,
    ROUND(SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) * 100, 2) AS mortality_rate,
    ROUND((SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) - 
          1.96 * SQRT(SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) * 
          (1 - SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*))) / COUNT(*))) * 100, 2) AS ci_lower,
    ROUND((SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) + 
          1.96 * SQRT(SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) * 
          (1 - SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*))) / COUNT(*))) * 100, 2) AS ci_upper
FROM stroke_cohort sc
INNER JOIN icu_status icu
    ON sc.hadm_id = icu.hadm_id
GROUP BY icu_group, los_group, comorbidity_group
ORDER BY icu_group, los_group, comorbidity_group;