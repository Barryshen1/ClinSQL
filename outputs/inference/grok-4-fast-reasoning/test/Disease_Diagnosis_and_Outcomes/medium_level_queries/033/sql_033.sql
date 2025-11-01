WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = a.hadm_id
    ) AS has_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 82 AND 92
    AND a.dischtime IS NOT NULL
    AND EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'T8%')
          OR (d.icd_version = 9 
              AND (d.icd_code LIKE '996%' OR d.icd_code LIKE '997%' 
                   OR d.icd_code LIKE '998%' OR d.icd_code LIKE '999%'))
        )
    )
),
comms AS (
  SELECT 
    c.*,
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
     WHERE d.hadm_id = c.hadm_id AND d.seq_num > 1
    ) AS comm_count
  FROM cohort c
)
SELECT 
  CASE WHEN has_icu THEN 'ICU' ELSE 'non-ICU' END AS location,
  CASE WHEN los_days <= 5 THEN '<=5' ELSE '>5' END AS los_bin,
  CASE 
    WHEN comm_count <= 1 THEN '0-1'
    WHEN comm_count = 2 THEN '2'
    ELSE '>=3'
  END AS comm_bin,
  COUNT(*) AS N,
  ROUND(AVG(comm_count), 2) AS avg_comorbidity_count,
  ROUND(100.0 * AVG(hospital_expire_flag), 2) AS in_hospital_mortality_pct
FROM comms
GROUP BY location, los_bin, comm_bin
ORDER BY location, los_bin, comm_bin;