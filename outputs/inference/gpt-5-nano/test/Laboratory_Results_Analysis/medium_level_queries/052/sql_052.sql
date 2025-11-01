WITH ami_admits AS (
  -- Admissions in AMI for male patients aged 76-86
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id  = a.hadm_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      (di.icd_version = 9  AND di.icd_code LIKE '410%') OR
      (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
    )
),
first_troponin AS (
  -- First Troponin I measurement per AMI admission
  SELECT le.hadm_id,
         le.charttime,
         le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  JOIN ami_admits AS aa
    ON le.hadm_id = aa.hadm_id
  WHERE LOWER(dli.label) LIKE '%troponin i%'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),
classified AS (
  -- Bin the first Troponin I into Normal / Borderline / Elevated
  SELECT
    CASE
      WHEN t.valuenum <= 0.04 THEN 'Normal'
      WHEN t.valuenum > 0.04 AND t.valuenum <= 0.40 THEN 'Borderline'
      ELSE 'Elevated'
    END AS bin,
    t.valuenum
  FROM first_troponin t
),
-- total admissions with a first Troponin I measurement (within AMI, male 76-86)
total_cte AS (
  SELECT COUNT(*) AS total
  FROM classified
),
-- For each bin, compute quantiles (Q1, median, Q3) using 100-quantiles approximation
bin_quantiles AS (
  SELECT bin, APPROX_QUANTILES(valuenum, 100) AS quantiles
  FROM classified
  GROUP BY bin
)
SELECT
  c.bin AS troponin_bin,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / total_cte.total, 2) AS pct,
  AVG(c.valuenum) AS mean_value,
  -- Q1 (25th), median (50th), Q3 (75th) using the per-bin quantiles
  q.quantiles[OFFSET(24)] AS q1,
  q.quantiles[OFFSET(50)] AS median,
  q.quantiles[OFFSET(75)] AS q3
FROM classified AS c
CROSS JOIN total_cte
JOIN bin_quantiles AS q
  ON c.bin = q.bin
GROUP BY c.bin, q.quantiles, total_cte.total
ORDER BY troponin_bin;