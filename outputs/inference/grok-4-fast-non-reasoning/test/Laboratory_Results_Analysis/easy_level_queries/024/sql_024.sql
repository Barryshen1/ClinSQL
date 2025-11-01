WITH sepsis_admissions AS (
  SELECT DISTINCT 
    ad.subject_id,
    ad.hadm_id,
    ad.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ad.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON di.icd_code = icd.icd_code
    AND di.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND icd.icd_code LIKE 'A41%'
    -- Include both primary and secondary diagnoses
    AND di.seq_num BETWEEN 1 AND 15
),
first_platelets AS (
  SELECT 
    sa.hadm_id,
    sa.admittime,
    le.charttime,
    le.valuenum AS platelet_count
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE li.label = 'Platelet'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= sa.admittime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sa.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT 
  STDDEV(platelet_count) AS sd_platelet_count,
  COUNT(*) AS num_admissions
FROM first_platelets;