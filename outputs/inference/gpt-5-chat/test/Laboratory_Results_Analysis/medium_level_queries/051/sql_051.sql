WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
   AND adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
   AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND (
      (diag.icd_version = 9 AND (
         diag.icd_code LIKE '410%' OR  -- AMI
         diag.icd_code LIKE '411%'))   -- Unstable angina
      OR
      (diag.icd_version = 10 AND (
         diag.icd_code LIKE 'I20%' OR
         diag.icd_code LIKE 'I21%' OR
         diag.icd_code LIKE 'I22%' OR
         diag.icd_code LIKE 'I24%'))
    )
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id,
         le.charttime, le.valuenum, le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND (
      LOWER(dl.label) LIKE '%troponin t (high sensitivity)%'
      OR LOWER(dl.label) LIKE '%hs-tn%'
      OR LOWER(dl.label) LIKE '%high sensitivity troponin t%'
    )
),
first_tnI AS (
  SELECT subject_id, hadm_id, valuenum, valueuom
  FROM (
    SELECT tl.*,
           ROW_NUMBER() OVER (PARTITION BY tl.hadm_id ORDER BY charttime) AS rn
    FROM troponin_labs tl
    JOIN acs_admissions aa
      ON tl.subject_id = aa.subject_id
     AND tl.hadm_id = aa.hadm_id
  ) sub
  WHERE rn = 1
),
categorized AS (
  SELECT f.subject_id, f.hadm_id,
         CASE
           WHEN valuenum < 14 THEN 'Normal'
           WHEN valuenum >= 14 AND valuenum < 50 THEN 'Borderline'
           ELSE 'Myocardial Injury'
         END AS tn_category,
         DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM first_tnI f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON f.subject_id = adm.subject_id
   AND f.hadm_id = adm.hadm_id
)
SELECT tn_category,
       COUNT(*) AS patient_count,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
       ROUND(AVG(los_days), 2) AS mean_los_days
FROM categorized
GROUP BY tn_category
ORDER BY tn_category;