WITH first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems di
    ON le.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'troponin t'
    AND LOWER(di.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
),
troponin_classified AS (
  SELECT
    ft.hadm_id,
    CASE
      WHEN ft.valuenum < 14 THEN 'Normal'
      WHEN ft.valuenum BETWEEN 14 AND 19 THEN 'Borderline'
      WHEN ft.valuenum >= 20 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS troponin_category
  FROM
    first_troponin ft
  WHERE
    ft.rn = 1
),
filtered_admissions AS (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    tc.troponin_category
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    troponin_classified tc
    ON a.hadm_id = tc.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
)
SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los), 2) AS mean_los
FROM
  filtered_admissions
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;