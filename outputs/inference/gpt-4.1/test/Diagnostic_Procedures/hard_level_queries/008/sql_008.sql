WITH ugib_icd_codes AS (
  -- List of ICD codes for upper GI bleeding (ICD-10 and ICD-9)
  SELECT 'K920' AS icd_code, 10 AS icd_version UNION ALL -- Hematemesis
  SELECT 'K921', 10 UNION ALL -- Melena
  SELECT 'K250', 10 UNION ALL -- Gastric ulcer with hemorrhage
  SELECT 'K251', 10 UNION ALL
  SELECT 'K252', 10 UNION ALL
  SELECT 'K253', 10 UNION ALL
  SELECT 'K254', 10 UNION ALL
  SELECT 'K255', 10 UNION ALL
  SELECT 'K256', 10 UNION ALL
  SELECT 'K257', 10 UNION ALL
  SELECT 'K258', 10 UNION ALL
  SELECT 'K259', 10 UNION ALL
  SELECT 'K260', 10 UNION ALL -- Duodenal ulcer with hemorrhage
  SELECT 'K261', 10 UNION ALL
  SELECT 'K262', 10 UNION ALL
  SELECT 'K263', 10 UNION ALL
  SELECT 'K264', 10 UNION ALL
  SELECT 'K265', 10 UNION ALL
  SELECT 'K266', 10 UNION ALL
  SELECT 'K267', 10 UNION ALL
  SELECT 'K268', 10 UNION ALL
  SELECT 'K269', 10 UNION ALL
  SELECT 'K270', 10 UNION ALL -- Peptic ulcer with hemorrhage
  SELECT 'K271', 10 UNION ALL
  SELECT 'K272', 10 UNION ALL
  SELECT 'K273', 10 UNION ALL
  SELECT 'K274', 10 UNION ALL
  SELECT 'K275', 10 UNION ALL
  SELECT 'K276', 10 UNION ALL
  SELECT 'K277', 10 UNION ALL
  SELECT 'K278', 10 UNION ALL
  SELECT 'K279', 10 UNION ALL
  SELECT 'K280', 10 UNION ALL -- Gastrojejunal ulcer with hemorrhage
  SELECT 'K281', 10 UNION ALL
  SELECT 'K282', 10 UNION ALL
  SELECT 'K283', 10 UNION ALL
  SELECT 'K284', 10 UNION ALL
  SELECT 'K285', 10 UNION ALL
  SELECT 'K286', 10 UNION ALL
  SELECT 'K287', 10 UNION ALL
  SELECT 'K288', 10 UNION ALL
  SELECT 'K289', 10 UNION ALL
  SELECT 'K290', 10 UNION ALL -- Acute hemorrhagic gastritis
  SELECT 'K31811', 10 UNION ALL -- Dieulafoy lesion
  SELECT 'I8501', 10 UNION ALL -- Esophageal varices with bleeding
  SELECT 'K226', 10 UNION ALL -- Mallory-Weiss syndrome
  SELECT 'K228', 10 UNION ALL -- Other specified diseases of esophagus with bleeding
  -- Add ICD-9 equivalents if needed
  SELECT '5780', 9 UNION ALL -- Hematemesis
  SELECT '5781', 9 UNION ALL -- Blood in stool
  SELECT '5789', 9 -- GI hemorrhage, unspecified
),
ugib_admissions AS (
  -- Admissions with UGIB diagnosis
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  JOIN ugib_icd_codes uicd
    ON diag.icd_code = uicd.icd_code AND diag.icd_version = uicd.icd_version
),
cohort AS (
  -- Male ICU patients aged 48-58 with UGIB
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime,
    pat.anchor_age,
    adm.dischtime,
    adm.admittime,
    adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  JOIN ugib_admissions ua
    ON icu.subject_id = ua.subject_id AND icu.hadm_id = ua.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
),
diagnostic_procedures AS (
  -- Procedures in first 24h of ICU stay
  SELECT
    proc.subject_id,
    proc.hadm_id,
    coh.stay_id,
    proc.chartdate,
    proc.icd_code,
    proc.icd_version,
    dip.long_title
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd proc
  JOIN cohort coh
    ON proc.subject_id = coh.subject_id AND proc.hadm_id = coh.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
  WHERE proc.chartdate >= coh.icu_intime
    AND proc.chartdate < DATETIME_ADD(coh.icu_intime, INTERVAL 24 HOUR)
    -- Optionally filter for diagnostic procedures only:
    AND (
      LOWER(dip.long_title) LIKE '%endoscopy%' OR
      LOWER(dip.long_title) LIKE '%diagnostic%' OR
      LOWER(dip.long_title) LIKE '%biopsy%' OR
      LOWER(dip.long_title) LIKE '%imaging%' OR
      LOWER(dip.long_title) LIKE '%ultrasound%' OR
      LOWER(dip.long_title) LIKE '%ct%' OR
      LOWER(dip.long_title) LIKE '%mri%' OR
      LOWER(dip.long_title) LIKE '%x-ray%' OR
      LOWER(dip.long_title) LIKE '%esophagogastroduodenoscopy%' OR
      LOWER(dip.long_title) LIKE '%gastroscopy%' OR
      LOWER(dip.long_title) LIKE '%colonoscopy%'
    )
),
procedure_counts AS (
  -- Count diagnostic procedures per ICU stay
  SELECT
    coh.subject_id,
    coh.hadm_id,
    coh.stay_id,
    coh.icu_intime,
    coh.icu_outtime, -- FIXED: was coh.outtime
    coh.anchor_age,
    coh.admittime,
    coh.dischtime,
    coh.hospital_expire_flag,
    COUNT(DISTINCT dp.icd_code) AS procedure_count
  FROM cohort coh
  LEFT JOIN diagnostic_procedures dp
    ON coh.subject_id = dp.subject_id AND coh.hadm_id = dp.hadm_id AND coh.stay_id = dp.stay_id
  GROUP BY
    coh.subject_id, coh.hadm_id, coh.stay_id, coh.icu_intime, coh.icu_outtime,
    coh.anchor_age, coh.admittime, coh.dischtime, coh.hospital_expire_flag
),
quintiles AS (
  -- Assign quintiles based on procedure count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS procedure_quintile
  FROM procedure_counts
),
summary AS (
  -- Aggregate outcomes per quintile
  SELECT
    procedure_quintile,
    COUNT(*) AS n_stays,
    AVG(procedure_count) AS avg_procedures,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_hospital_los_days,
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_pct
  FROM quintiles
  GROUP BY procedure_quintile
  ORDER BY procedure_quintile
)
SELECT
  procedure_quintile AS quintile,
  n_stays,
  avg_procedures,
  avg_hospital_los_days,
  in_hospital_mortality_pct
FROM summary
ORDER BY quintile;