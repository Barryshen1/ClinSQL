WITH heart_failure_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 5 AND 8 THEN '5-8'
    END AS stay_group,
    CASE WHEN icu.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS icu_use
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON d.icd_code = ddi.icd_code
      AND d.icd_version = ddi.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(ddi.long_title) LIKE '%heart failure%'
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 8
),
imaging_counts AS (
  -- HOSP radiography/CT via HCPCS events
  SELECT
    hadm_id,
    COUNT(*) AS img_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    LOWER(short_description) LIKE '%xray%'
    OR LOWER(short_description) LIKE '%ct%'
  GROUP BY hadm_id

  UNION ALL

  -- ICU radiography/CT via procedureevents + d_items
  SELECT
    pe.hadm_id,
    COUNT(*) AS img_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%xray%'
    OR LOWER(di.label) LIKE '%ct%'
  GROUP BY pe.hadm_id
),
adm_counts AS (
  -- Sum imaging counts per admission; if none, default to zero
  SELECT
    h.hadm_id,
    COALESCE(SUM(ic.img_count), 0) AS radiology_count
  FROM
    heart_failure_adm h
    LEFT JOIN imaging_counts ic
      ON h.hadm_id = ic.hadm_id
  GROUP BY h.hadm_id
),
stats AS (
  SELECT
    h.stay_group,
    h.icu_use,
    ac.radiology_count
  FROM
    heart_failure_adm h
    JOIN adm_counts ac
      ON h.hadm_id = ac.hadm_id
)
SELECT
  stay_group,
  icu_use,
  quartiles[OFFSET(1)] AS p25,
  quartiles[OFFSET(2)] AS p50,
  quartiles[OFFSET(3)] AS p75
FROM (
  SELECT
    stay_group,
    icu_use,
    APPROX_QUANTILES(radiology_count, 4) AS quartiles
  FROM stats
  GROUP BY stay_group, icu_use
)
ORDER BY stay_group, icu_use;