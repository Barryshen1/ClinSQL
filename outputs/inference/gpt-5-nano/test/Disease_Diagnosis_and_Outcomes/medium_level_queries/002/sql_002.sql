WITH female_ami AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('female', 'f')
    AND p.anchor_age BETWEEN 62 AND 72
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
        ON di.icd_code = ddi.icd_code
       AND di.icd_version = ddi.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(ddi.long_title) LIKE '%myocardial infarction%'
    )
),
valid_cases AS (
  SELECT f.subject_id, f.hadm_id, f.admittime, f.dischtime, f.deathtime, f.hospital_expire_flag
  FROM female_ami f
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
      ON di.icd_code = ddi.icd_code
     AND di.icd_version = ddi.icd_version
    WHERE di.subject_id = f.subject_id
      AND di.hadm_id = f.hadm_id
      AND (LOWER(ddi.long_title) LIKE '%shock%' OR LOWER(ddi.long_title) LIKE '%respiratory failure%')
  )
),
diag_ckd AS (
  SELECT hadm_id,
         MAX(CASE
               WHEN LOWER(long_title) LIKE '%chronic kidney disease%'
                    OR LOWER(long_title) LIKE '%kidney disease%'
               THEN 1 ELSE 0 END) AS ckd_present
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  GROUP BY hadm_id
),
diag_diab AS (
  SELECT hadm_id,
         MAX(CASE
               WHEN LOWER(long_title) LIKE '%diabetes mellitus%'
                    OR LOWER(long_title) LIKE '%diabetes%'
               THEN 1 ELSE 0 END) AS diabetes_present
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  GROUP BY hadm_id
),
outs AS (
  SELECT v.subject_id,
         v.hadm_id,
         v.admittime,
         v.dischtime,
         v.deathtime,
         v.hospital_expire_flag,
         DATE(v.dischtime) AS dis_date,
         DATE_DIFF(DATE(v.dischtime), DATE(v.admittime), DAY) AS los_days,
         CASE WHEN DATE_DIFF(DATE(v.dischtime), DATE(v.admittime), DAY) <= 5 THEN 'LE5' ELSE 'GT5' END AS los_group,
         COALESCE(dc.ckd_present, 0) AS ckd_present,
         COALESCE(dd.diabetes_present, 0) AS diabetes_present,
         CASE WHEN (v.deathtime IS NOT NULL) OR (v.hospital_expire_flag = 1) THEN 1 ELSE 0 END AS mort
  FROM valid_cases v
  LEFT JOIN diag_ckd dc ON v.hadm_id = dc.hadm_id
  LEFT JOIN diag_diab dd ON v.hadm_id = dd.hadm_id
),
metrics AS (
  SELECT los_group,
         COUNT(*) AS n,
         AVG(mort) AS mort_rate,
         AVG(ckd_present) AS ckd_prev,
         AVG(diabetes_present) AS diabetes_prev
  FROM outs
  GROUP BY los_group
)
SELECT a.los_group,
       a.n,
       a.mort_rate,
       a.ckd_prev,
       a.diabetes_prev,
       (a.mort_rate - b.mort_rate) AS abs_mort_diff_vs_other,
       (CASE WHEN b.mort_rate = 0 THEN NULL ELSE a.mort_rate / b.mort_rate END) AS rel_mort_rr_vs_other
FROM metrics AS a
JOIN metrics AS b
  ON (a.los_group = 'LE5' AND b.los_group = 'GT5')
   OR (a.los_group = 'GT5' AND b.los_group = 'LE5')
ORDER BY a.los_group;