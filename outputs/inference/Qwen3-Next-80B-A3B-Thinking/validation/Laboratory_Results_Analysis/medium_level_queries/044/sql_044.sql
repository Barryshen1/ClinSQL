WITH first_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE di.label = 'Troponin T'
    AND l.valuenum IS NOT NULL
)
SELECT
  COUNT(*) AS n,
  AVG(ft.valuenum) AS mean,
  STDDEV(ft.valuenum) AS sd,
  MIN(ft.valuenum) AS min,
  MAX(ft.valuenum) AS max,
  PERCENTILE_CONT(ft.valuenum, 0.5) WITHIN GROUP (ORDER BY ft.valuenum) AS median,
  PERCENTILE_CONT(ft.valuenum, 0.25) WITHIN GROUP (ORDER BY ft.valuenum) AS p25,
  PERCENTILE_CONT(ft.valuenum, 0.75) WITHIN GROUP (ORDER BY ft.valuenum) AS p75
FROM first_troponin ft
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON ft.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
WHERE ft.rn = 1
  AND p.gender = 'M'
  AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 54 AND 64
  AND ft.valuenum > 0.01;