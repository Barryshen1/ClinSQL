WITH cohort AS (
  -- Base cohort: female surgical admissions aged 51-61
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admission_type = 'SURGICAL'
    AND a.hadm_id IS NOT NULL
),

med_complexity AS (
  -- Calculate 24h medication complexity per admission
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    SUM(
      CASE 
        WHEN LOWER(pr.drug) LIKE '%morphine%' OR LOWER(pr.drug) LIKE '%fentanyl%' OR LOWER(pr.drug) LIKE '%oxycodone%'  -- Opioids
          OR LOWER(pr.drug) LIKE '%heparin%' OR LOWER(pr.drug) LIKE '%warfarin%' OR LOWER(pr.drug) LIKE '%enoxaparin%'  -- Anticoagulants
          OR LOWER(pr.drug) LIKE '%midazolam%' OR LOWER(pr.drug) LIKE '%propofol%' OR LOWER(pr.drug) LIKE '%fentanyl%'  -- Sedatives (overlap noted)
          OR LOWER(pr.drug) LIKE '%norepinephrine%' OR LOWER(pr.drug) LIKE '%dopamine%'  -- Vasopressors
        THEN 2 
        ELSE 1 
      END
    ) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
    AND pr.drug IS NOT NULL  -- Valid drugs only
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

readmissions AS (
  -- Flag 30-day readmissions for non-expired cases
  SELECT 
    m.*,
    CASE 
      WHEN m.hospital_expire_flag = 0 THEN
        EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` next_a
          WHERE next_a.subject_id = m.subject_id
            AND next_a.hadm_id != m.hadm_id
            AND next_a.admittime > m.dischtime
            AND next_a.admittime <= TIMESTAMP_ADD(m.dischtime, INTERVAL 30 DAY)
        )
      ELSE FALSE
    END AS readmit_flag
  FROM med_complexity m
),

quartiles AS (
  -- Assign quartiles based on complexity score
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY complexity_score ASC) AS quartile
  FROM readmissions
)

-- Aggregate outcomes by quartile
SELECT 
  quartile,
  COUNT(*) AS count_admissions,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  (SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*)) AS mortality_pct,
  (SUM(CAST(readmit_flag AS INT64)) * 100.0 / SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)) AS readmission_pct
FROM quartiles
GROUP BY quartile
ORDER BY quartile ASC;