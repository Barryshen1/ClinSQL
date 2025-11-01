WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND a.hadm_id IN (
      SELECT DISTINCT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.long_title LIKE '%transplant%'
    )
),

med_score AS (
  SELECT 
    c.hadm_id,
    SUM(
      1 + 
      CASE 
        WHEN LOWER(p.route) LIKE '%iv%' THEN 1 
        WHEN LOWER(p.route) LIKE '%oral%' THEN 0 
        ELSE 0.5 
      END +
      CASE 
        WHEN p.doses_per_24_hrs = 1 THEN 0
        WHEN p.doses_per_24_hrs = 2 THEN 0.5
        WHEN p.doses_per_24_hrs >= 3 THEN 1
        ELSE 0 
      END
    ) AS complexity_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  WHERE 
    p.starttime >= c.admittime 
    AND p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.hadm_id
),

adm_with_next AS (
  SELECT 
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

cohort_outcomes AS (
  SELECT 
    c.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 0
      WHEN a.next_admittime IS NOT NULL 
        AND a.next_admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS readmission_30day
  FROM cohort c
  INNER JOIN adm_with_next a 
    ON c.hadm_id = a.hadm_id
),

combined AS (
  SELECT 
    c.hadm_id,
    COALESCE(m.complexity_score, 0) AS complexity_score,  -- Handle no prescriptions
    o.los,
    o.hospital_expire_flag,
    o.readmission_30day
  FROM cohort c
  LEFT JOIN med_score m ON c.hadm_id = m.hadm_id
  INNER JOIN cohort_outcomes o ON c.hadm_id = o.hadm_id
),

quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM combined
)

SELECT 
  quartile,
  COUNT(*) AS n,
  AVG(complexity_score) AS mean_score,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(readmission_30day) AS readmission_30day
FROM quartiles
GROUP BY quartile
ORDER BY quartile;