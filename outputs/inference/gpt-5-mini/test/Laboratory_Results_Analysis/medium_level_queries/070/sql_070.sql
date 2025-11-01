WITH troponin_items AS (
  -- find lab itemids that represent Troponin I
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),

first_troponin_per_admission AS (
  -- select the earliest Troponin I measurement per hospital admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.valueuom,
    le.charttime,
    le.storetime,
    le.ref_range_upper,
    LOWER(COALESCE(le.flag, '')) AS flag
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items d ON le.itemid = d.itemid
  WHERE le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime, le.storetime) = 1
),

eligible_admissions AS (
  -- filter to male patients age 90-100, admissions with chest pain diagnosis,
  -- and where the initial troponin is "elevated"
  SELECT
    ft.hadm_id,
    ft.subject_id,
    ft.valuenum,
    ft.valueuom,
    ft.charttime,
    ft.ref_range_upper,
    ft.flag
  FROM first_troponin_per_admission ft
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ft.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    -- admission has any diagnosis whose description mentions "chest pain"
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%chest pain%'
    )
    -- initial troponin considered elevated if numeric > ref_range_upper (when available)
    -- or the lab flag suggests high/abnormal
    AND (
      (ft.ref_range_upper IS NOT NULL AND ft.valuenum > ft.ref_range_upper)
      OR REGEXP_CONTAINS(ft.flag, r'(h|hh|high|abnormal|a)')
    )
)

SELECT
  quartiles[OFFSET(1)] AS p25,
  quartiles[OFFSET(2)] AS p50,
  quartiles[OFFSET(3)] AS p75,
  quartiles[OFFSET(0)] AS min_value,
  quartiles[OFFSET(4)] AS max_value,
  -- compute the count separately as a scalar subquery to avoid mixing aggregates with non-aggregates
  (SELECT COUNT(1) FROM eligible_admissions) AS n_admissions_included
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quartiles
  FROM eligible_admissions
);