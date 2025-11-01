WITH stroke_male_40_50 AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d.icd_version = 9 AND (
         d.icd_code LIKE '430%' OR
         d.icd_code LIKE '431%' OR
         d.icd_code LIKE '432%'))
      OR
      (d.icd_version = 10 AND (
         d.icd_code LIKE 'I60%' OR
         d.icd_code LIKE 'I61%' OR
         d.icd_code LIKE 'I62%'))
    )
),
cohort_abn AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(DISTINCT le.itemid) AS abn_lab_count
  FROM stroke_male_40_50 c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL
    AND LOWER(le.flag) LIKE 'abnormal%'
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_quartiles AS (
  SELECT ca.*,
         NTILE(4) OVER (ORDER BY abn_lab_count) AS abn_quartile
  FROM cohort_abn ca
),
cohort_summary AS (
  SELECT cq.abn_quartile,
         COUNT(*) AS n_patients,
         AVG(DATETIME_DIFF(s.dischtime, s.admittime, DAY)) AS avg_los_days,
         AVG(s.hospital_expire_flag) AS mortality_rate
  FROM cohort_with_quartiles cq
  JOIN stroke_male_40_50 s
    ON cq.subject_id = s.subject_id AND cq.hadm_id = s.hadm_id
  GROUP BY cq.abn_quartile
),
-- per-lab abnormal rates for cohort
cohort_lab_rates AS (
  SELECT le.itemid,
         COUNTIF(LOWER(le.flag) LIKE 'abnormal%') / COUNT(*) AS cohort_abn_rate
  FROM stroke_male_40_50 c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY le.itemid
),
-- per-lab abnormal rates for all inpatients
all_lab_rates AS (
  SELECT le.itemid,
         COUNTIF(LOWER(le.flag) LIKE 'abnormal%') / COUNT(*) AS all_abn_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  GROUP BY le.itemid
)
SELECT 
  cs.abn_quartile,
  cs.n_patients,
  cs.avg_los_days,
  cs.mortality_rate,
  lr.itemid,
  lr.cohort_abn_rate,
  ar.all_abn_rate
FROM cohort_summary cs
LEFT JOIN cohort_lab_rates lr
  ON TRUE -- all quartiles share same per-lab rate; closer join possible if needed by quartile
LEFT JOIN all_lab_rates ar
  ON lr.itemid = ar.itemid
ORDER BY cs.abn_quartile, lr.itemid;