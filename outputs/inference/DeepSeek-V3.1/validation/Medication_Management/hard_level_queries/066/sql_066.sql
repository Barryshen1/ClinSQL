WITH transplant_codes AS (
  -- Common transplant-related ICD codes (diagnoses)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND icd_code LIKE 'Z94%')  -- Transplanted organ status
    OR (icd_version = 9 AND icd_code IN ('V42.0', 'V42.1', 'V42.2', 'V42.3', 'V42.4', 'V42.5', 'V42.6', 'V42.7', 'V42.8', 'V42.9'))
    -- Add other transplant-related codes if needed
),

cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN transplant_codes tc
    ON diag.icd_code = tc.icd_code AND diag.icd_version = tc.icd_version
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
),

medications AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id
),

cohort_with_meds AS (
  SELECT 
    c.*,
    COALESCE(m.complexity_score, 0) AS complexity_score
  FROM cohort c
  LEFT JOIN medications m
    ON c.hadm_id = m.hadm_id AND c.subject_id = m.subject_id
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
  FROM cohort_with_meds
),

readmissions AS (
  SELECT 
    q1.hadm_id,
    COUNT(q2.hadm_id) > 0 AS readmitted_30d
  FROM quartiles q1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` q2
    ON q1.subject_id = q2.subject_id
    AND q2.admittime > q1.dischtime
    AND q2.admittime <= DATETIME_ADD(q1.dischtime, INTERVAL 30 DAY)
  GROUP BY q1.hadm_id
)

SELECT 
  complexity_quartile,
  COUNT(*) AS n,
  AVG(complexity_score) AS mean_complexity_score,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(CAST(readmitted_30d AS INT)) AS readmission_30d_rate
FROM quartiles q
LEFT JOIN readmissions r
  ON q.hadm_id = r.hadm_id
GROUP BY complexity_quartile
ORDER BY complexity_quartile;