WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),
dx AS (
  SELECT hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '250%')
        OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
      THEN 1 ELSE 0 END) AS has_dm,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '428%')
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
      THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_filtered AS (
  SELECT c.subject_id, c.hadm_id
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.has_dm = 1 AND dx.has_hf = 1
),
adm_times AS (
  SELECT hadm_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
presc_class AS (
  SELECT hadm_id,
         CASE 
           WHEN LOWER(drug) LIKE '%metformin%' 
             OR LOWER(drug) LIKE '%insulin%' 
             OR LOWER(drug) LIKE '%glipizide%' 
             OR LOWER(drug) LIKE '%glyburide%' 
             OR LOWER(drug) LIKE '%pioglitazone%' 
             OR LOWER(drug) LIKE '%sitagliptin%' 
             OR LOWER(drug) LIKE '%linagliptin%' 
           THEN 'antidiabetic'
           WHEN LOWER(drug) LIKE '%metoprolol%' 
             OR LOWER(drug) LIKE '%atenolol%' 
             OR LOWER(drug) LIKE '%carvedilol%' 
             OR LOWER(drug) LIKE '%propranolol%' 
             OR LOWER(drug) LIKE '%nadolol%' 
           THEN 'beta_blocker'
           WHEN LOWER(drug) LIKE '%lisinopril%' 
             OR LOWER(drug) LIKE '%enalapril%' 
             OR LOWER(drug) LIKE '%ramipril%' 
             OR LOWER(drug) LIKE '%captopril%' 
             OR LOWER(drug) LIKE '%losartan%' 
             OR LOWER(drug) LIKE '%valsartan%' 
             OR LOWER(drug) LIKE '%candesartan%' 
             OR LOWER(drug) LIKE '%irbesartan%' 
             OR LOWER(drug) LIKE '%sacubitril%' 
           THEN 'ace_arb_arni'
           WHEN LOWER(drug) LIKE '%furosemide%' 
             OR LOWER(drug) LIKE '%bumetanide%' 
             OR LOWER(drug) LIKE '%torsemide%' 
           THEN 'loop_diuretic'
           ELSE NULL
         END AS med_class,
         TIMESTAMP(starttime) AS starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),
presc_flagged AS (
  SELECT cf.hadm_id, pc.med_class,
    MAX(
      CASE 
        WHEN pc.starttime BETWEEN TIMESTAMP(adm.admittime) 
                               AND TIMESTAMP_ADD(TIMESTAMP(adm.admittime), INTERVAL 24 HOUR)
        THEN 1 ELSE 0 
      END
    ) AS first24h_flag,
    MAX(
      CASE 
        WHEN pc.starttime BETWEEN TIMESTAMP_SUB(TIMESTAMP(adm.dischtime), INTERVAL 24 HOUR) 
                               AND TIMESTAMP(adm.dischtime)
        THEN 1 ELSE 0 
      END
    ) AS last24h_flag
  FROM cohort_filtered cf
  JOIN adm_times adm
    ON cf.hadm_id = adm.hadm_id
  JOIN presc_class pc
    ON cf.hadm_id = pc.hadm_id
  WHERE pc.med_class IS NOT NULL
  GROUP BY cf.hadm_id, pc.med_class
),
counts AS (
  SELECT med_class,
    COUNT(DISTINCT CASE WHEN first24h_flag = 1 THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS pct_first24h,
    COUNT(DISTINCT CASE WHEN last24h_flag = 1 THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS pct_last24h,
    COUNT(DISTINCT CASE WHEN first24h_flag = 1 AND last24h_flag = 1 THEN hadm_id END) AS n_continued,
    COUNT(DISTINCT CASE WHEN first24h_flag = 0 AND last24h_flag = 1 THEN hadm_id END) AS n_initiated_late,
    COUNT(DISTINCT CASE WHEN first24h_flag = 1 AND last24h_flag = 0 THEN hadm_id END) AS n_discontinued,
    COUNT(DISTINCT hadm_id) AS total_cases
  FROM presc_flagged
  GROUP BY med_class
)
SELECT med_class, pct_first24h, pct_last24h, n_continued, n_initiated_late, n_discontinued, total_cases
FROM counts
ORDER BY med_class;