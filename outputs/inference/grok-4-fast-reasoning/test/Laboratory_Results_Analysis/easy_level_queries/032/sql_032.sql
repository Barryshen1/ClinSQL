WITH copd_adms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (CAST(p.anchor_age AS INT64) + EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64)) = 90
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'J44%') 
      OR 
      (d.icd_version = 9 AND (d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code = '496'))
    )
),
eligible_labs AS (
  SELECT l.hadm_id, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN copd_adms c 
    ON l.hadm_id = c.hadm_id
  WHERE l.itemid = 50912
    AND l.valuenum IS NOT NULL
    AND l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
)
SELECT STDDEV(avg_serum_creat) AS sd_of_avg_serum_creatinine_first_24h
FROM (
  SELECT AVG(valuenum) AS avg_serum_creat
  FROM eligible_labs
  GROUP BY hadm_id
);