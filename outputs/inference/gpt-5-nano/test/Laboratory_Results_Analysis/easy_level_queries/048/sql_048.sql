WITH COPD_women AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND (
      (di.icd_version = 9 AND di.icd_code IN ('491','492','496'))
      OR
      (di.icd_version = 10 AND (
          di.icd_code LIKE 'J41%' OR
          di.icd_code LIKE 'J42%' OR
          di.icd_code LIKE 'J43%' OR
          di.icd_code LIKE 'J44%'
      ))
    )
),
creat_mean AS (
  SELECT a.hadm_id,
         AVG(le.valuenum) AS creat_mean_24h
  FROM COPD_women cw
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = cw.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
    AND LOWER(dli.label) LIKE '%creatinine%'
  GROUP BY a.hadm_id
)

SELECT quantiles[OFFSET(75)] AS p75_creatinine_mean_24h
FROM (
  SELECT APPROX_QUANTILES(creat_mean_24h, 101) AS quantiles
  FROM creat_mean
);