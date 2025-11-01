WITH acs_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      (d.icd_version = 9 AND (
        d.icd_code LIKE '410%' OR d.icd_code = '4111'
      ))
      OR
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code = 'I200'
      ))
    )
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_trop AS (
  SELECT l.subject_id, l.hadm_id,
         MIN(l.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_items ti ON l.itemid = ti.itemid
  JOIN acs_patients acs ON l.subject_id = acs.subject_id AND l.hadm_id = acs.hadm_id
  WHERE l.valuenum IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
),
index_trop AS (
  SELECT l.subject_id, l.hadm_id, l.valuenum,
    CASE
      WHEN l.valuenum < 0.03 THEN 'Normal/Minimal'
      WHEN l.valuenum >= 0.03 AND l.valuenum < 0.10 THEN 'Borderline'
      WHEN l.valuenum >= 0.10 THEN 'Elevated'
      ELSE 'Unknown'
    END AS trop_category
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_items ti ON l.itemid = ti.itemid
  JOIN first_trop ft
    ON l.subject_id = ft.subject_id
   AND l.hadm_id = ft.hadm_id
   AND l.charttime = ft.first_charttime
)
SELECT 
  it.trop_category,
  COUNT(*) AS patient_count,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage_of_cohort,
  SUM(CASE WHEN acs.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100 * SUM(CASE WHEN acs.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_rate_pct
FROM index_trop it
JOIN acs_patients acs
  ON it.subject_id = acs.subject_id AND it.hadm_id = acs.hadm_id
GROUP BY it.trop_category
ORDER BY it.trop_category;