WITH acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    AND (
         -- ICD-9 ACS
         (d.icd_version = 9 AND (
           d.icd_code LIKE '410%' OR    -- AMI
           d.icd_code = '4111' OR       -- unstable angina
           d.icd_code = '41181' OR
           d.icd_code = '41189'
         ))
         -- ICD-10 ACS
         OR (d.icd_version = 10 AND (
           d.icd_code LIKE 'I20.0%' OR  -- unstable angina
           d.icd_code LIKE 'I21%' OR    -- STEMI/NSTEMI
           d.icd_code LIKE 'I22%'       -- subsequent MI
         ))
    )
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime,
         le.valuenum, le.valueuom,
         ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND (LOWER(di.label) LIKE '%high%' OR LOWER(di.label) LIKE '%hs%')
    AND le.valuenum IS NOT NULL
    AND LOWER(le.valueuom) IN ('ng/l','ng/ml') -- adjust as needed
),
first_tnt AS (
  SELECT subject_id, hadm_id, valuenum, valueuom
  FROM troponin_labs
  WHERE rn = 1
),
categorized AS (
  SELECT acs.subject_id, acs.hadm_id,
         CASE
           WHEN ft.valuenum < 14 THEN 'Normal'
           WHEN ft.valuenum >= 14 AND ft.valuenum < 52 THEN 'Borderline'
           WHEN ft.valuenum >= 52 THEN 'Myocardial Injury'
           ELSE 'Unknown'
         END AS tnt_category,
         DATETIME_DIFF(acs.dischtime, acs.admittime, DAY) AS los
  FROM acs_admissions acs
  JOIN first_tnt ft
    ON acs.subject_id = ft.subject_id AND acs.hadm_id = ft.hadm_id
)
SELECT tnt_category,
       COUNT(*) AS num_admissions,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_admissions,
       ROUND(AVG(los), 2) AS mean_los_days
FROM categorized
WHERE tnt_category != 'Unknown'
GROUP BY tnt_category
ORDER BY tnt_category;