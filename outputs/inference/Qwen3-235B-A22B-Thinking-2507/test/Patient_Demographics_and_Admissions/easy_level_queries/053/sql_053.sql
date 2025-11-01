WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND a.hospital_expire_flag = 0
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'N17%'
    )
),
next_admissions AS (
  SELECT 
    e.hadm_id,
    e.dischtime,
    MIN(a2.admittime) AS next_admittime
  FROM eligible_admissions e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON e.subject_id = a2.subject_id
    AND a2.admittime > e.dischtime
  GROUP BY e.hadm_id, e.dischtime
),
readmission_flags AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND next_admittime <= dischtime + INTERVAL '30' DAY 
        THEN 1 
      ELSE 0 
    END AS readmit_30d
  FROM next_admissions
)
SELECT 
  STDDEV_POP(readmit_30d) AS std_readmit_30d
FROM readmission_flags;