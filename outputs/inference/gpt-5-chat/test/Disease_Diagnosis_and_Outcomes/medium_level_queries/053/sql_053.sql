WITH dx_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%aspiration pneumonia%' THEN 1 ELSE 0 END) AS aspiration_flag,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%pneumonia%' THEN 1 ELSE 0 END) AS any_pneumonia_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  GROUP BY di.subject_id, di.hadm_id
),
comorb_counts AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN dx_flags df
    ON di.subject_id = df.subject_id
    AND di.hadm_id = df.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di_icd
    ON di.icd_code = di_icd.icd_code
    AND di.icd_version = di_icd.icd_version
  WHERE NOT (LOWER(di_icd.long_title) LIKE '%pneumonia%')
  GROUP BY di.subject_id, di.hadm_id
),
icu_flag AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    CASE WHEN MIN(TIMESTAMP_DIFF(icu.intime, adm.admittime, HOUR)) < 24 THEN 1 ELSE 0 END AS ICU_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.subject_id = icu.subject_id
    AND adm.hadm_id = icu.hadm_id
  GROUP BY adm.subject_id, adm.hadm_id
),
base AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    CASE WHEN df.aspiration_flag = 1 THEN 'Aspiration'
         WHEN df.any_pneumonia_flag = 1 THEN 'Community-acquired'
         ELSE NULL END AS pneumonia_type,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) >= 8 THEN '>=8'
      ELSE 'Other'
    END AS los_group,
    icu.ICU_day1,
    adm.hospital_expire_flag,
    cb.comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN dx_flags df
    ON adm.subject_id = df.subject_id
    AND adm.hadm_id = df.hadm_id
  LEFT JOIN comorb_counts cb
    ON adm.subject_id = cb.subject_id
    AND adm.hadm_id = cb.hadm_id
  JOIN icu_flag icu
    ON adm.subject_id = icu.subject_id
    AND adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
    AND df.any_pneumonia_flag = 1
    AND (df.aspiration_flag = 1 OR df.any_pneumonia_flag = 1)
)
SELECT
  pneumonia_type,
  los_group,
  ICU_day1,
  COUNT(*) AS n_admissions,
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_percent,
  AVG(comorb_count) AS avg_comorbidity_count
FROM base
WHERE los_group IN ('1-3','4-7','>=8')
GROUP BY pneumonia_type, los_group, ICU_day1
ORDER BY pneumonia_type, los_group, ICU_day1;