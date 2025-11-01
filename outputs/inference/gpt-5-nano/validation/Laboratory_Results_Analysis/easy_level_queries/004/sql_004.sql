WITH sepsis_admissions AS (
  SELECT DISTINCT a.subject_id,
                  a.hadm_id,
                  a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%sepsis%'
    AND p.gender = 'Female'
    AND p.anchor_age BETWEEN 71 AND 81
),

platelet_per_admission AS (
  SELECT s.hadm_id,
         AVG(le.valuenum) AS mean_platelets_24h
  FROM sepsis_admissions AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = s.hadm_id
   AND le.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%platelet%'
    AND le.charttime >= s.admittime
    AND le.charttime <= TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
  GROUP BY s.hadm_id
)

SELECT quantiles[OFFSET(50)] AS median_platelets_24h
FROM (
  SELECT APPROX_QUANTILES(mean_platelets_24h, 101) AS quantiles
  FROM platelet_per_admission
  WHERE mean_platelets_24h IS NOT NULL
);