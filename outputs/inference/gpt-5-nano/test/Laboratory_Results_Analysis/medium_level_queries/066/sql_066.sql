WITH chest_pain_cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),

-- Part 2: extract the initial hs-TnT value for each such admission
initial_hstnt AS (
  SELECT
    cpc.hadm_id,
    le.charttime,
    le.valuenum AS initial_tn
  FROM chest_pain_cohort AS cpc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = cpc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE (
        LOWER(dli.label) LIKE '%troponin%'
        OR LOWER(dli.label) LIKE '%hs-troponin%'
        OR LOWER(dli.label) LIKE '%hs troponin%'
      )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY cpc.hadm_id ORDER BY le.charttime) = 1
)

-- Part 3: compute category stats from the initial hs-TnT values
SELECT
  CASE
    WHEN initial_tn < 14 THEN 'Normal'
    WHEN initial_tn < 52 THEN 'Borderline'
    ELSE 'Myocardial injury'
  END AS category,
  COUNT(*) AS cnt,
  100.0 * COUNT(*) / (SELECT COUNT(*) FROM initial_hstnt) AS pct,
  AVG(initial_tn) AS mean,
  -- Median and IQR using approximate quantiles (100 bins)
  APPROX_QUANTILES(initial_tn, 100)[OFFSET(50)] AS median,
  (APPROX_QUANTILES(initial_tn, 100)[OFFSET(75)]
     - APPROX_QUANTILES(initial_tn, 100)[OFFSET(25)]
  ) AS iqr
FROM initial_hstnt
GROUP BY category
ORDER BY category;