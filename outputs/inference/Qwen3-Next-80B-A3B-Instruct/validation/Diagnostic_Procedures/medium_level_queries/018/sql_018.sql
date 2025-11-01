WITH hemorrhagic_stroke_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(d_icd.long_title) LIKE '%hemorrhagic stroke%'
       OR LOWER(d_icd.long_title) LIKE '%intracerebral hemorrhage%'
       OR LOWER(d_icd.long_title) LIKE '%subarachnoid hemorrhage%'
       OR LOWER(d_icd.long_title) LIKE '%intracranial hemorrhage%'
       OR d.icd_code IN ('430', '431', 'I60', 'I61', 'I62')
),
icu_stays_with_los AS (
  SELECT i.stay_id, i.hadm_id, i.los,
         CASE 
           WHEN i.los BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN i.los BETWEEN 5 AND 7 THEN '5-7 days'
         END AS los_group
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN hemorrhagic_stroke_patients h ON i.subject_id = h.subject_id AND i.hadm_id = h.hadm_id
  WHERE i.los >= 1 AND i.los <= 7
),
ultrasound_procedures AS (
  SELECT pe.stay_id, COUNT(*) AS ultrasound_count
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ultrasound%'
  GROUP BY pe.stay_id
),
final_counts AS (
  SELECT 
    i.los_group,
    COALESCE(u.ultrasound_count, 0) AS ultrasounds_per_stay
  FROM icu_stays_with_los i
  LEFT JOIN ultrasound_procedures u ON i.stay_id = u.stay_id
)
SELECT 
  los_group,
  AVG(ultrasounds_per_stay) AS mean_ultrasounds,
  MIN(ultrasounds_per_stay) AS min_ultrasounds,
  MAX(ultrasounds_per_stay) AS max_ultrasounds
FROM final_counts
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY los_group;