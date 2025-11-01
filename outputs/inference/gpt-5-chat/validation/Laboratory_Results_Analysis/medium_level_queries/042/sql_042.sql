WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  SELECT sub.subject_id, sub.hadm_id, sub.charttime, sub.valuenum, sub.valueuom,
         sub.ref_range_lower, sub.ref_range_upper
  FROM (
    SELECT l.subject_id, l.hadm_id, l.charttime, l.valuenum, l.valueuom,
           l.ref_range_lower, l.ref_range_upper,
           ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_items ti
      ON l.itemid = ti.itemid
    JOIN cohort c
      ON l.hadm_id = c.hadm_id
    WHERE l.valuenum IS NOT NULL
  ) sub
  WHERE rn = 1
),
categorized AS (
  SELECT f.subject_id, f.hadm_id,
         CASE
           WHEN f.ref_range_upper IS NOT NULL AND f.valuenum <= f.ref_range_upper
             THEN 'normal'
           WHEN f.ref_range_upper IS NOT NULL AND f.valuenum <= f.ref_range_upper * 1.2
             THEN 'borderline'
           WHEN f.ref_range_upper IS NOT NULL
             THEN 'elevated'
           ELSE 'unknown'
         END AS troponin_category
  FROM first_troponin f
),
final AS (
  SELECT cat.troponin_category,
         COUNT(*) AS num_admissions,
         ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_admissions,
         SUM(c.hospital_expire_flag) AS num_deaths,
         ROUND(SUM(c.hospital_expire_flag) * 100.0 / COUNT(*), 2) AS pct_mortality
  FROM categorized cat
  JOIN cohort c
    ON cat.hadm_id = c.hadm_id
  GROUP BY cat.troponin_category
)
SELECT * 
FROM final
ORDER BY troponin_category;