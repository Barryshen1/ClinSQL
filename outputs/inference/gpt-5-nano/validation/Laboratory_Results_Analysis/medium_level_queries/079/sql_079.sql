WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = p.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '786.5%')
),
troponin_init AS (
  SELECT t.hadm_id, t.troponin_value
  FROM (
    SELECT l.hadm_id,
           l.valuenum AS troponin_value,
           ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
      ON l.itemid = d.itemid
    WHERE l.hadm_id IN (SELECT hadm_id FROM cohort)
      AND LOWER(d.label) LIKE '%troponin%' AND LOWER(d.label) LIKE '%t%'
  ) t
  WHERE t.rn = 1
)
SELECT
  PERCENTILE_CONT(troponin_value, 0.25) OVER () AS p25,
  PERCENTILE_CONT(troponin_value, 0.50) OVER () AS p50,
  PERCENTILE_CONT(troponin_value, 0.75) OVER () AS p75,
  MIN(troponin_value) OVER () AS min_value,
  MAX(troponin_value) OVER () AS max_value
FROM troponin_init
WHERE troponin_value > 0.01
LIMIT 1;