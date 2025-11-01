WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
  ON
    i.hadm_id = d1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd1
  ON
    d1.icd_code = d_icd1.icd_code
    AND d1.icd_version = d_icd1.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
  ON
    i.hadm_id = d2.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd2
  ON
    d2.icd_code = d_icd2.icd_code
    AND d2.icd_version = d_icd2.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(d_icd1.long_title) LIKE '%type 2 diabetes%'
    AND LOWER(d_icd2.long_title) LIKE '%heart failure%'
),

meds_first_24h AS (
  SELECT DISTINCT
    c.stay_id,
    CASE
      WHEN LOWER(di.label) LIKE '%insulin%' OR LOWER(di.label) LIKE '%metformin%' THEN 'Antidiabetic'
      WHEN LOWER(di.label) LIKE '%metoprolol%' OR LOWER(di.label) LIKE '%carvedilol%' THEN 'Beta-blocker'
      WHEN LOWER(di.label) LIKE '%lisinopril%' OR LOWER(di.label) LIKE '%losartan%' OR LOWER(di.label) LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(di.label) LIKE '%furosemide%' OR LOWER(di.label) LIKE '%bumetanide%' OR LOWER(di.label) LIKE '%torsemide%' THEN 'Loop Diuretic'
    END AS drug_class
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` iv
  ON
    c.stay_id = iv.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    iv.itemid = di.itemid
  WHERE
    iv.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND (
      LOWER(di.label) LIKE '%insulin%' OR LOWER(di.label) LIKE '%metformin%' OR
      LOWER(di.label) LIKE '%metoprolol%' OR LOWER(di.label) LIKE '%carvedilol%' OR
      LOWER(di.label) LIKE '%lisinopril%' OR LOWER(di.label) LIKE '%losartan%' OR LOWER(di.label) LIKE '%sacubitril%' OR
      LOWER(di.label) LIKE '%furosemide%' OR LOWER(di.label) LIKE '%bumetanide%' OR LOWER(di.label) LIKE '%torsemide%'
    )
),

meds_final_48h AS (
  SELECT DISTINCT
    c.stay_id,
    CASE
      WHEN LOWER(di.label) LIKE '%insulin%' OR LOWER(di.label) LIKE '%metformin%' THEN 'Antidiabetic'
      WHEN LOWER(di.label) LIKE '%metoprolol%' OR LOWER(di.label) LIKE '%carvedilol%' THEN 'Beta-blocker'
      WHEN LOWER(di.label) LIKE '%lisinopril%' OR LOWER(di.label) LIKE '%losartan%' OR LOWER(di.label) LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(di.label) LIKE '%furosemide%' OR LOWER(di.label) LIKE '%bumetanide%' OR LOWER(di.label) LIKE '%torsemide%' THEN 'Loop Diuretic'
    END AS drug_class
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` iv
  ON
    c.stay_id = iv.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    iv.itemid = di.itemid
  WHERE
    iv.starttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 48 HOUR) AND c.outtime
    AND (
      LOWER(di.label) LIKE '%insulin%' OR LOWER(di.label) LIKE '%metformin%' OR
      LOWER(di.label) LIKE '%metoprolol%' OR LOWER(di.label) LIKE '%carvedilol%' OR
      LOWER(di.label) LIKE '%lisinopril%' OR LOWER(di.label) LIKE '%losartan%' OR LOWER(di.label) LIKE '%sacubitril%' OR
      LOWER(di.label) LIKE '%furosemide%' OR LOWER(di.label) LIKE '%bumetanide%' OR LOWER(di.label) LIKE '%torsemide%'
    )
),

combined AS (
  SELECT
    f.stay_id,
    f.drug_class,
    'First24h' AS period
  FROM
    meds_first_24h f
  UNION ALL
  SELECT
    fi.stay_id,
    fi.drug_class,
    'Final48h' AS period
  FROM
    meds_final_48h fi
),

summary AS (
  SELECT
    drug_class,
    period,
    COUNT(DISTINCT stay_id) AS patient_count
  FROM
    combined
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    drug_class,
    period
),

pivot_summary AS (
  SELECT
    drug_class,
    SUM(CASE WHEN period = 'First24h' THEN patient_count ELSE 0 END) AS first_24h_count,
    SUM(CASE WHEN period = 'Final48h' THEN patient_count ELSE 0 END) AS final_48h_count
  FROM
    summary
  GROUP BY
    drug_class
),

status_flags AS (
  SELECT
    COALESCE(f.stay_id, fi.stay_id) AS stay_id,
    COALESCE(f.drug_class, fi.drug_class) AS drug_class,
    CASE
      WHEN f.drug_class IS NOT NULL AND fi.drug_class IS NOT NULL THEN 'Continued'
      WHEN f.drug_class IS NULL AND fi.drug_class IS NOT NULL THEN 'Initiated'
      WHEN f.drug_class IS NOT NULL AND fi.drug_class IS NULL THEN 'Discontinued'
    END AS status
  FROM
    (SELECT DISTINCT stay_id, drug_class FROM meds_first_24h) f
  FULL OUTER JOIN
    (SELECT DISTINCT stay_id, drug_class FROM meds_final_48h) fi
  ON
    f.stay_id = fi.stay_id
    AND f.drug_class = fi.drug_class
  WHERE
    COALESCE(f.drug_class, fi.drug_class) IS NOT NULL
),

status_counts AS (
  SELECT
    drug_class,
    status,
    COUNT(*) AS count
  FROM
    status_flags
  GROUP BY
    drug_class,
    status
)

SELECT
  ps.drug_class,
  ps.first_24h_count,
  ps.final_48h_count,
  COALESCE(sc1.count, 0) AS continued,
  COALESCE(sc2.count, 0) AS initiated,
  COALESCE(sc3.count, 0) AS discontinued
FROM
  pivot_summary ps
LEFT JOIN
  status_counts sc1
ON
  ps.drug_class = sc1.drug_class AND sc1.status = 'Continued'
LEFT JOIN
  status_counts sc2
ON
  ps.drug_class = sc2.drug_class AND sc2.status = 'Initiated'
LEFT JOIN
  status_counts sc3
ON
  ps.drug_class = sc3.drug_class AND sc3.status = 'Discontinued'
ORDER BY
  ps.drug_class;