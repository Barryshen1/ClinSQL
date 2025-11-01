WITH ich_patients AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON d.subject_id = p.subject_id
  WHERE 
    (d.icd_version = 9 AND d.icd_code IN ('430', '431')) OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%'))
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
  GROUP BY d.subject_id, d.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.gender, p.anchor_age
),

gcs_data AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MIN(c.valuenum) AS gcs_min
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN ich_patients i 
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  WHERE c.itemid = 223900
    AND c.charttime BETWEEN i.admittime AND DATETIME_ADD(i.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

hematoma_volume AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(c.valuenum) AS hematoma_vol
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN ich_patients i 
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  WHERE c.itemid = 220766
    AND c.charttime BETWEEN i.admittime AND DATETIME_ADD(i.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

intraventricular AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    MAX(CASE 
      WHEN (d2.icd_version = 9 AND d2.icd_code = '431.0') 
        OR (d2.icd_version = 10 AND d2.icd_code = 'I61.0') THEN 1 
      ELSE 0 
    END) AS intraventricular_flag
  FROM ich_patients d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
    ON d.subject_id = d2.subject_id AND d.hadm_id = d2.hadm_id
  GROUP BY d.subject_id, d.hadm_id
),

infratentorial AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    MAX(CASE 
      WHEN (d2.icd_version = 9 AND d2.icd_code = '431.5') 
        OR (d2.icd_version = 10 AND d2.icd_code = 'I61.5') THEN 1 
      ELSE 0 
    END) AS infratentorial_flag
  FROM ich_patients d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
    ON d.subject_id = d2.subject_id AND d.hadm_id = d2.hadm_id
  GROUP BY d.subject_id, d.hadm_id
),

cardiac_complications AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    MAX(CASE 
      WHEN (d2.icd_version = 9 AND d2.icd_code LIKE '410%') 
        OR (d2.icd_version = 10 AND d2.icd_code LIKE 'I21%') THEN 1 
      ELSE 0 
    END) AS cardiac_complication
  FROM ich_patients d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
    ON d.subject_id = d2.subject_id AND d.hadm_id = d2.hadm_id
  GROUP BY d.subject_id, d.hadm_id
),

neurologic_complications AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    MAX(CASE 
      WHEN (d2.icd_version = 9 AND d2.icd_code LIKE '345%') 
        OR (d2.icd_version = 10 AND d2.icd_code LIKE 'G40%') THEN 1 
      ELSE 0 
    END) AS neurologic_complication
  FROM ich_patients d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
    ON d.subject_id = d2.subject_id AND d.hadm_id = d2.hadm_id
  GROUP BY d.subject_id, d.hadm_id
),

ich_scores AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.hospital_expire_flag,
    g.gcs_min,
    h.hematoma_vol,
    iv.intraventricular_flag,
    it.infratentorial_flag,
    cc.cardiac_complication,
    nc.neurologic_complication,
    CASE 
      WHEN g.gcs_min BETWEEN 3 AND 4 THEN 2
      WHEN g.gcs_min BETWEEN 5 AND 12 THEN 1
      ELSE 0
    END + 
    CASE WHEN h.hematoma_vol >= 30 THEN 2 ELSE 0 END +
    iv.intraventricular_flag +
    it.infratentorial_flag AS ich_score
  FROM ich_patients i
  LEFT JOIN gcs_data g 
    ON i.subject_id = g.subject_id AND i.hadm_id = g.hadm_id
  LEFT JOIN hematoma_volume h 
    ON i.subject_id = h.subject_id AND i.hadm_id = h.hadm_id
  LEFT JOIN intraventricular iv 
    ON i.subject_id = iv.subject_id AND i.hadm_id = iv.hadm_id
  LEFT JOIN infratentorial it 
    ON i.subject_id = it.subject_id AND i.hadm_id = it.hadm_id
  LEFT JOIN cardiac_complications cc 
    ON i.subject_id = cc.subject_id AND i.hadm_id = cc.hadm_id
  LEFT JOIN neurologic_complications nc 
    ON i.subject_id = nc.subject_id AND i.hadm_id = nc.hadm_id
  WHERE g.gcs_min IS NOT NULL AND h.hematoma_vol IS NOT NULL
)

SELECT 
  NTILE(4) OVER (ORDER BY ich_score) AS quartile,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(cardiac_complication) AS cardiac_complication_rate,
  AVG(neurologic_complication) AS neurologic_complication_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATE_DIFF(a.dischtime, a.admittime, DAY)) AS median_los_survivors
FROM ich_scores
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON ich_scores.subject_id = a.subject_id AND ich_scores.hadm_id = a.hadm_id
WHERE ich_scores.hospital_expire_flag = 0
GROUP BY quartile
ORDER BY quartile;