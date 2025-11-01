WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  -- Link to label for ICD filtering
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dx
    ON d.icd_code = dx.icd_code AND d.icd_version = dx.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
cohort_with_conditions AS (
  SELECT c.subject_id, c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY c.subject_id, c.hadm_id
  HAVING COUNTIF(
            (di.icd_version = 9 AND di.icd_code LIKE '250%')
         OR (di.icd_version = 10 AND di.icd_code LIKE 'E1%')
       ) > 0
     AND COUNTIF(
            (di.icd_version = 9 AND di.icd_code IN ('42821','42823','42833','42843'))
         OR (di.icd_version = 10 AND di.icd_code IN ('I5021','I5023','I5033','I5043'))
       ) > 0
),
admission_times AS (
  SELECT cw.subject_id, cw.hadm_id, a.admittime, a.dischtime
  FROM cohort_with_conditions cw
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cw.subject_id = a.subject_id AND cw.hadm_id = a.hadm_id
),
drug_initiations AS (
  SELECT DISTINCT
    adm.hadm_id,
    CASE
      WHEN UPPER(pr.drug) LIKE '%INSULIN%' THEN 'Insulin'
      WHEN UPPER(pr.drug) LIKE '%METFORMIN%'
        OR UPPER(pr.drug) LIKE '%GLIPIZIDE%'
        OR UPPER(pr.drug) LIKE '%GLYBURIDE%'
        OR UPPER(pr.drug) LIKE '%PIOGLITAZONE%'
        OR UPPER(pr.drug) LIKE '%SITAGLIPTIN%'
        OR UPPER(pr.drug) LIKE '%LINAGLIPTIN%'
        OR UPPER(pr.drug) LIKE '%DAPAGLIFLOZIN%'
        OR UPPER(pr.drug) LIKE '%CANAGLIFLOZIN%'
        OR UPPER(pr.drug) LIKE '%EMPAGLIFLOZIN%' THEN 'Oral agent'
      ELSE NULL
    END AS drug_class,
    CASE
      WHEN pr.starttime BETWEEN adm.admittime AND adm.admittime + INTERVAL 24 HOUR
        THEN 'First 24h'
      WHEN pr.starttime BETWEEN adm.dischtime - INTERVAL 24 HOUR AND adm.dischtime
        THEN 'Final 24h'
      ELSE NULL
    END AS time_window
  FROM admission_times adm
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON adm.subject_id = pr.subject_id AND adm.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),
counts AS (
  SELECT
    drug_class,
    time_window,
    COUNT(DISTINCT hadm_id) AS n_admissions
  FROM drug_initiations
  WHERE drug_class IS NOT NULL AND time_window IS NOT NULL
  GROUP BY drug_class, time_window
),
total AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM admission_times
)
SELECT 
  c.drug_class,
  c.time_window,
  ROUND(100.0 * c.n_admissions / t.total_admissions, 2) AS initiation_rate_pct,
  CASE
    WHEN c.time_window = 'Final 24h' THEN
      ROUND(100.0 * c.n_admissions / t.total_admissions, 2)
      - (
        SELECT ROUND(100.0 * cf.n_admissions / t.total_admissions, 2)
        FROM counts cf
        WHERE cf.drug_class = c.drug_class AND cf.time_window = 'First 24h'
      )
    ELSE NULL
  END AS abs_pct_point_diff_vs_first
FROM counts c
CROSS JOIN total t
ORDER BY drug_class, time_window;