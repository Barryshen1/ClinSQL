WITH pancreatitis_matches AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      -- age at admission using anchor_age/anchor_year
      WHEN p.anchor_year IS NOT NULL THEN p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
      ELSE NULL
    END AS age_at_admit,
    LOWER(p.gender) AS gender,
    di.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pancreatitis%'
),

pancreatitis_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_pancreatitis,
    MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary_pancreatitis,
    age_at_admit,
    gender
  FROM pancreatitis_matches
  GROUP BY hadm_id, age_at_admit, gender
  HAVING age_at_admit BETWEEN 51 AND 61
     AND gender = 'm'
     AND (MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) = 1
          OR MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) = 1)
),

pancreatitis_adms AS (
  -- per admission: determine pancreatitis_type (primary takes precedence)
  SELECT
    m.hadm_id,
    m.subject_id,
    m.admittime,
    m.dischtime,
    m.los_days,
    m.age_at_admit,
    CASE
      WHEN pf.has_primary_pancreatitis = 1 THEN 'primary'
      WHEN pf.has_secondary_pancreatitis = 1 THEN 'secondary'
      ELSE NULL
    END AS pancreatitis_type
  FROM pancreatitis_matches AS m
  JOIN pancreatitis_flags pf
    ON m.hadm_id = pf.hadm_id
  WHERE pf.has_primary_pancreatitis = 1 OR pf.has_secondary_pancreatitis = 1
),

imaging_counts AS (
  SELECT st.hadm_id,
         COUNT(DISTINCT ce.charttime) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS st
    ON ce.stay_id = st.stay_id
  WHERE LOWER(di.label) LIKE '%x-ray%' OR LOWER(di.label) LIKE '%ct%'
  GROUP BY st.hadm_id
),

final AS (
  SELECT
    pa.pancreatitis_type,
    CASE
      WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group,
    COUNT(DISTINCT pa.subject_id) AS patient_count,
    AVG(COALESCE(ic.imaging_count, 0)) AS mean_radiography_cts_per_admission
  FROM pancreatitis_adms AS pa
  LEFT JOIN imaging_counts AS ic
    ON pa.hadm_id = ic.hadm_id
  WHERE pa.los_days BETWEEN 1 AND 7
  GROUP BY pa.pancreatitis_type, los_group
)

SELECT *
FROM final
ORDER BY los_group, pancreatitis_type;