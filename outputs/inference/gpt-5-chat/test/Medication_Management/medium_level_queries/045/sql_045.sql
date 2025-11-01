WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  -- get diabetes flag
  JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE ( (icd_version = 9 AND icd_code LIKE '250%')
         OR (icd_version = 10 AND icd_code LIKE 'E1%' ) )
    GROUP BY hadm_id
  ) diab ON adm.hadm_id = diab.hadm_id
  -- get heart failure flag
  JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE ( (icd_version = 9 AND icd_code LIKE '428%')
         OR (icd_version = 10 AND icd_code LIKE 'I50%' ) )
    GROUP BY hadm_id
  ) hf ON adm.hadm_id = hf.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 54 AND 64
),
med_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
              AND pr.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR
             THEN 1 ELSE 0 END) AS insulin_first12h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%'
               OR LOWER(pr.drug) LIKE '%glipizide%'
               OR LOWER(pr.drug) LIKE '%glyburide%'
               OR LOWER(pr.drug) LIKE '%glyclamide%'
               OR LOWER(pr.drug) LIKE '%pioglitazone%'
               OR LOWER(pr.drug) LIKE '%sitagliptin%'
               OR LOWER(pr.drug) LIKE '%linagliptin%'
               OR LOWER(pr.drug) LIKE '%repaglinide%'
               AND pr.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR
             THEN 1 ELSE 0 END) AS oral_first12h,

    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
              AND pr.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime
             THEN 1 ELSE 0 END) AS insulin_final48h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%'
               OR LOWER(pr.drug) LIKE '%glipizide%'
               OR LOWER(pr.drug) LIKE '%glyburide%'
               OR LOWER(pr.drug) LIKE '%glyclamide%'
               OR LOWER(pr.drug) LIKE '%pioglitazone%'
               OR LOWER(pr.drug) LIKE '%sitagliptin%'
               OR LOWER(pr.drug) LIKE '%linagliptin%'
               OR LOWER(pr.drug) LIKE '%repaglinide%'
               AND pr.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime
             THEN 1 ELSE 0 END) AS oral_final48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
prevalence AS (
  SELECT
    COUNT(*) AS n_patients,
    100.0 * SUM(insulin_first12h) / COUNT(*) AS insulin_first12h_pct,
    100.0 * SUM(oral_first12h) / COUNT(*)    AS oral_first12h_pct,
    100.0 * SUM(insulin_final48h) / COUNT(*) AS insulin_final48h_pct,
    100.0 * SUM(oral_final48h) / COUNT(*)    AS oral_final48h_pct
  FROM med_flags
)
SELECT
  n_patients,
  insulin_first12h_pct,
  insulin_final48h_pct,
  (insulin_final48h_pct - insulin_first12h_pct) AS insulin_net_change_pp,
  oral_first12h_pct,
  oral_final48h_pct,
  (oral_final48h_pct - oral_first12h_pct) AS oral_net_change_pp
FROM prevalence;