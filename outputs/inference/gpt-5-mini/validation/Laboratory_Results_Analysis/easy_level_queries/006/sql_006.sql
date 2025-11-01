WITH copd_admissions AS (
  -- Admissions for female patients age 50 with at least one COPD-related diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 50
    AND (
      LOWER(dd.long_title) LIKE '%chronic obstructive%'
      OR LOWER(dd.long_title) LIKE '%copd%'
      OR LOWER(dd.long_title) LIKE '%chronic bronchitis%'
      OR LOWER(dd.long_title) LIKE '%emphysema%'
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime
),

sodium_items AS (
  -- Lab itemids corresponding to serum/plasma/blood sodium measurements
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%sodium%'
    AND LOWER(COALESCE(fluid, '')) IN ('blood', 'serum', 'plasma')
),

admission_nadir_sodium AS (
  -- For each qualifying admission, compute the nadir (minimum) serum sodium measured during the hospital stay
  SELECT
    ca.hadm_id,
    MIN(le.valuenum) AS nadir_sodium
  FROM
    copd_admissions ca
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON le.hadm_id = ca.hadm_id
    JOIN sodium_items si
      ON le.itemid = si.itemid
  WHERE
    le.valuenum IS NOT NULL
    -- Ensure the lab occurred during the admission window
    AND le.charttime BETWEEN ca.admittime AND ca.dischtime
  GROUP BY
    ca.hadm_id
  HAVING
    MIN(le.valuenum) IS NOT NULL
)

-- Final: compute the standard deviation of the nadir sodium values across admissions
SELECT
  COUNT(*) AS admissions_count,
  STDDEV_POP(nadir_sodium) AS sd_nadir_sodium,
  AVG(nadir_sodium) AS mean_nadir_sodium,
  MIN(nadir_sodium) AS min_nadir_sodium,
  MAX(nadir_sodium) AS max_nadir_sodium
FROM
  admission_nadir_sodium;