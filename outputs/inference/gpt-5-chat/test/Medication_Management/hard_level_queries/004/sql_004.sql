WITH stroke_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 10 AND icd_code LIKE 'I63%')
     OR (icd_version = 9 AND (
           icd_code LIKE '433%' OR
           icd_code LIKE '434%' OR
           icd_code = '436'
         )
        )
),
stroke_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         p.gender,
         p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN stroke_codes sc
      ON d.icd_code = sc.icd_code AND d.icd_version = sc.icd_version
    WHERE d.hadm_id = a.hadm_id
  )
  AND p.gender = 'F'
  AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 48 AND 58
),
drug_list AS (
  -- Example known NTI, CYP3A4 substrate drugs - adjust as needed
  SELECT 'cyclosporine' AS drug
  UNION ALL SELECT 'tacrolimus'
  UNION ALL SELECT 'carbamazepine'
  UNION ALL SELECT 'quinidine'
  UNION ALL SELECT 'sirolimus'
  UNION ALL SELECT 'everolimus'
),
cyp3a4_nti AS (
  SELECT DISTINCT pr.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN drug_list dl
    ON LOWER(pr.drug) LIKE CONCAT('%', dl.drug, '%')
),
complexity AS (
  SELECT hadm_id, MAX(CAST(drg_severity AS INT64)) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY hadm_id
),
base_cohort AS (
  SELECT sa.*,
         cyp.hadm_id IS NOT NULL AS cyp3a4_nti_flag,
         comp.complexity_score,
         DATE_DIFF(sa.dischtime, sa.admittime, DAY) AS los
  FROM stroke_admissions sa
  LEFT JOIN cyp3a4_nti cyp
    ON sa.hadm_id = cyp.hadm_id
  LEFT JOIN complexity comp
    ON sa.hadm_id = comp.hadm_id
),
percentiled AS (
  SELECT bc.*,
         PERCENT_RANK() OVER (ORDER BY complexity_score) AS complexity_percentile
  FROM base_cohort bc
),
summary AS (
  SELECT
    cyp3a4_nti_flag,
    COUNT(*) AS n_patients,
    AVG(complexity_score) AS avg_complexity,
    AVG(complexity_percentile) AS avg_percentile,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM percentiled
  GROUP BY cyp3a4_nti_flag
),
top_quartile AS (
  SELECT
    COUNT(*) AS n_top,
    AVG(los) AS avg_los_top,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_top
  FROM percentiled
  WHERE complexity_percentile >= 0.75
)
SELECT
  'group_summary' AS section,
  *
FROM summary
UNION ALL
SELECT
  'top_quartile' AS section,
  NULL AS cyp3a4_nti_flag,
  n_top AS n_patients,
  NULL AS avg_complexity,
  NULL AS avg_percentile,
  avg_los_top AS avg_los,
  mortality_rate_top AS mortality_rate
FROM top_quartile;