WITH female_80_90 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 80 AND 90
),
hemorrhagic_stroke AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I61%'
    AND di.icd_version = 10
),
eligible_admissions AS (
  SELECT i.hadm_id, i.stay_id, i.los, i.intime, i.outtime,
    CASE
      WHEN i.los >= 1 AND i.los <= 4 THEN '1-4'
      WHEN i.los >= 5 AND i.los <= 7 THEN '5-7'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  JOIN hemorrhagic_stroke hs ON i.hadm_id = hs.hadm_id
  JOIN female_80_90 f ON i.subject_id = f.subject_id
  WHERE i.los >= 1 AND i.los <= 7
),
ultrasound_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%ultrasound%'
    AND linksto = 'procedureevents'
),
ultrasounds_per_admission AS (
  SELECT
    ea.hadm_id,
    ea.los_group,
    COUNT(*) AS ultrasound_count
  FROM eligible_admissions ea
  JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents p
    ON ea.stay_id = p.stay_id
  JOIN ultrasound_items ui
    ON p.itemid = ui.itemid
  WHERE p.starttime >= ea.intime
    AND (p.endtime IS NULL OR p.endtime <= ea.outtime)
    AND p.starttime IS NOT NULL
  GROUP BY ea.hadm_id, ea.los_group
)
SELECT
  los_group,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM ultrasounds_per_admission
GROUP BY los_group
ORDER BY los_group;