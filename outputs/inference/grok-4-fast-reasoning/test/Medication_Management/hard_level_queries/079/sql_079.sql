WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admit_year
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1
    AND a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 89 AND 99
),
med_complexity AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    COUNT(DISTINCT pres.drug) AS num_unique_drugs
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.subject_id = pres.subject_id 
    AND c.hadm_id = pres.hadm_id
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
    AND pres.drug IS NOT NULL 
    AND pres.drug != ''
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime
),
base AS (
  SELECT 
    m.*,
    c.los_days,
    c.hospital_expire_flag,
    c.dischtime,
    CASE 
      WHEN c.hospital_expire_flag = 1 THEN 0
      ELSE COALESCE(
        (SELECT AS VALUE 1
         FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
         WHERE a2.subject_id = c.subject_id
           AND a2.hadm_id != c.hadm_id
           AND a2.admittime > c.dischtime
           AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
         LIMIT 1),
        0
      )
    END AS readmitted
  FROM 
    med_complexity m
  INNER JOIN 
    cohort c 
    ON m.hadm_id = c.hadm_id
)
SELECT 
  quintile,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_pct,
  ROUND(
    SAFE_DIVIDE(SUM(readmitted), SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)) * 100, 
    2
  ) AS readmission_rate_pct
FROM (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY num_unique_drugs ASC) AS quintile
  FROM base
)
GROUP BY quintile
ORDER BY quintile;