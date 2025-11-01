WITH population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.services` s 
      WHERE s.hadm_id = a.hadm_id 
        AND LOWER(s.curr_service) LIKE '%surg%'
    )
),
complexity AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drug_count
  FROM population p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.hadm_id = pr.hadm_id
  WHERE 
    pr.starttime >= p.admittime 
    AND pr.starttime < TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR)
  GROUP BY p.hadm_id
),
base AS (
  SELECT 
    p.*,
    COALESCE(c.unique_drug_count, 0) AS complexity_score,
    NTILE(4) OVER (ORDER BY COALESCE(c.unique_drug_count, 0)) AS quartile
  FROM population p
  LEFT JOIN complexity c ON p.hadm_id = c.hadm_id
),
all_admissions_for_base_patients AS (
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.subject_id IN (SELECT subject_id FROM base)
),
base_with_readmission AS (
  SELECT 
    b.*,
    CASE 
      WHEN aa.next_admittime <= TIMESTAMP_ADD(b.dischtime, INTERVAL 30 DAY) 
      THEN 1 
      ELSE 0 
    END AS readmission_30d
  FROM base b
  LEFT JOIN all_admissions_for_base_patients aa
    ON b.hadm_id = aa.hadm_id
)
SELECT
  quartile,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  AVG(readmission_30d) * 100 AS readmission_30d_rate,
  COUNT(*) AS count
FROM base_with_readmission
GROUP BY quartile
ORDER BY quartile;