WITH chest_pain_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),

-- Part 2: extract the first Troponin T value per admission
first_troponin_by_hadm AS (
  SELECT l.hadm_id,
         l.valuenum AS troponin_value
  FROM chest_pain_admissions cpa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = cpa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin%t%'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
)

-- Part 3: assemble results with mortality
SELECT
  CASE
    WHEN troponin_value <= 0.01 THEN 'Normal'
    WHEN troponin_value <= 0.04 THEN 'Borderline'
    ELSE 'Elevated'
  END AS troponin_category,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percent,
  SUM(in_hospital_death) / COUNT(*) AS in_hospital_mortality
FROM (
  SELECT f.hadm_id,
         f.troponin_value,
         CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hospital_death
  FROM first_troponin_by_hadm f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON f.hadm_id = a.hadm_id
) AS t
GROUP BY troponin_category
ORDER BY troponin_category;