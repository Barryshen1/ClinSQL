WITH ami_cohort AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON d.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
      (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '410'))
      OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I21'))
    )
),
tnt_labs AS (
  SELECT l.subject_id, l.hadm_id,
         l.charttime, l.valuenum, l.valueuom,
         di.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND LOWER(di.label) LIKE '%high%'
    AND l.valuenum IS NOT NULL
    AND LOWER(l.valueuom) = 'ng/l'
),
initial_tnt AS (
  SELECT t.subject_id, t.hadm_id,
         t.valuenum,
         t.charttime
  FROM (
    SELECT subject_id, hadm_id,
           valuenum, charttime,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM tnt_labs
  ) AS t
  WHERE t.rn = 1
),
categorized AS (
  SELECT i.subject_id, i.hadm_id, i.valuenum,
    CASE
      WHEN i.valuenum < 14 THEN 'Normal'
      WHEN i.valuenum >= 14 AND i.valuenum <= 50 THEN 'Borderline'
      WHEN i.valuenum > 50 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS category
  FROM initial_tnt AS i
)
SELECT category,
       COUNT(*) AS count,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM categorized
JOIN ami_cohort AS ac
  ON categorized.subject_id = ac.subject_id
 AND categorized.hadm_id = ac.hadm_id
GROUP BY category
ORDER BY category;