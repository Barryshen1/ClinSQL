WITH aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR), 24.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    -- restrict to admissions that have at least one AKI diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- common AKI ICD-9 and ICD-10 prefixes
          (d.icd_version = 9 AND d.icd_code LIKE '584%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%acute kidney%'
        )
    )
),

-- medication complexity and flags per admission
presc_by_adm AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    COALESCE(COUNT(DISTINCT LOWER(TRIM(prescriptions.drug))), 0) AS complexity,
    -- CNS-depressant heuristic flag: opioids, benzos, sedative/hypnotics, propofol, etc.
    MAX(
      CASE
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%morphine%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%fentanyl%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%hydromorphone%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%oxycod%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%hydrocod%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%codeine%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%tramadol%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%methadone%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%propofol%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%lorazepam%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%midazolam%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%alprazolam%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%diazepam%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%clonazepam%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%zolpidem%' THEN 1
        ELSE 0
      END
    ) AS has_cns,
    -- Nephrotoxic heuristic flag: vanco, aminoglycosides, cisplatin, amphotericin, NSAIDs, contrast, etc.
    MAX(
      CASE
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%vancomycin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%gentamicin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%tobramycin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%amikacin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%cisplatin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%amphotericin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%colistin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%acyclovir%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%ibuprofen%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%ketorolac%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%naproxen%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%indomethacin%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%contrast%' THEN 1
        WHEN LOWER(COALESCE(prescriptions.drug, '')) LIKE '%iodine%' THEN 1
        ELSE 0
      END
    ) AS has_neph
  FROM
    aki_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` prescriptions
      ON prescriptions.hadm_id = a.hadm_id
  GROUP BY
    a.hadm_id, a.subject_id
),

-- Combine admission-level metrics (admissions + med metrics)
adm_metrics AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.los_days,
    a.hospital_expire_flag,
    COALESCE(pba.complexity, 0) AS complexity,
    COALESCE(pba.has_cns, 0) AS has_cns,
    COALESCE(pba.has_neph, 0) AS has_neph,
    CASE
      WHEN COALESCE(pba.has_cns, 0) = 1 AND COALESCE(pba.has_neph, 0) = 1 THEN 'both_CNS_and_nephrotoxic'
      ELSE 'other_AKI'
    END AS cohort_label
  FROM
    aki_admissions a
    LEFT JOIN presc_by_adm pba USING(hadm_id)
)

-- Final aggregations per cohort, plus top-quartile (by complexity within each cohort) outcomes
SELECT
  cs.cohort_label,
  cs.n_admissions,
  -- complexity distribution: approx quartiles (25%, 50%, 75%) using APPROX_QUANTILES with 101 buckets
  cs.complexity_q25,
  cs.complexity_median,
  cs.complexity_q75,
  ROUND(cs.mean_complexity, 2) AS mean_complexity,
  -- overall outcomes for cohort
  ROUND(cs.mean_los_days, 2) AS overall_mean_los_days,
  ROUND(cs.mortality_rate, 4) AS overall_mortality_rate,
  -- top-quartile (complexity >= cohort 75th percentile) counts and outcomes
  COALESCE(tq.top_q_n, 0) AS top_quartile_n,
  COALESCE(ROUND(tq.top_q_mean_los_days, 2), 0) AS top_quartile_mean_los_days,
  COALESCE(ROUND(tq.top_q_mortality_rate, 4), 0) AS top_quartile_mortality_rate
FROM (
  -- cohort-level summary and quartiles
  SELECT
    cohort_label,
    COUNT(*) AS n_admissions,
    -- APPROX_QUANTILES returns an array where OFFSET(25) is approx 25th percentile, OFFSET(50) median, OFFSET(75) 75th
    APPROX_QUANTILES(complexity, 101)[OFFSET(25)] AS complexity_q25,
    APPROX_QUANTILES(complexity, 101)[OFFSET(50)] AS complexity_median,
    APPROX_QUANTILES(complexity, 101)[OFFSET(75)] AS complexity_q75,
    AVG(complexity) AS mean_complexity,
    AVG(los_days) AS mean_los_days,
    SUM(CAST(hospital_expire_flag AS INT64))/COUNT(*) AS mortality_rate
  FROM
    adm_metrics
  GROUP BY
    cohort_label
) cs
LEFT JOIN (
  -- compute top-quartile (within-cohort) outcomes by joining adm_metrics to cohort 75th percentile
  SELECT
    m.cohort_label,
    COUNT(*) AS top_q_n,
    AVG(m.los_days) AS top_q_mean_los_days,
    SUM(CAST(m.hospital_expire_flag AS INT64))/COUNT(*) AS top_q_mortality_rate
  FROM
    adm_metrics m
    JOIN (
      -- extract cohort-level 75th percentile
      SELECT
        cohort_label,
        APPROX_QUANTILES(complexity, 101)[OFFSET(75)] AS complexity_q75
      FROM adm_metrics
      GROUP BY cohort_label
    ) cohort_q
    ON m.cohort_label = cohort_q.cohort_label
  WHERE
    -- define top quartile as complexity >= 75th percentile for that cohort
    m.complexity >= cohort_q.complexity_q75
  GROUP BY
    m.cohort_label
) tq
  ON cs.cohort_label = tq.cohort_label
ORDER BY
  cs.cohort_label;