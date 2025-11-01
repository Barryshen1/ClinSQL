WITH
-- 1) admissions for female patients age 64-74
female_adms AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 64 AND 74
),

-- 2) determine AKI presence and whether primary vs secondary per admission
aki_flags AS (
  SELECT
    d.hadm_id,
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS STRING) LIKE '584%')
          OR (d.icd_version = 10 AND UPPER(d.icd_code) LIKE 'N17%')
        THEN CASE WHEN d.seq_num = 1 THEN 2 ELSE 1 END
        ELSE 0
      END
    ) AS aki_flag_rank
    -- aki_flag_rank: 0 = no AKI, 1 = AKI present only as secondary (seq_num>1), 2 = AKI present as primary (seq_num=1) (primary takes precedence)
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY
    d.hadm_id
),

-- 3) cohort: admissions meeting demographic criteria AND having AKI (primary or secondary)
cohort AS (
  SELECT
    fa.hadm_id,
    fa.subject_id,
    fa.admittime,
    CASE
      WHEN af.aki_flag_rank = 2 THEN 'primary'
      WHEN af.aki_flag_rank = 1 THEN 'secondary'
      ELSE NULL
    END AS aki_class
  FROM
    female_adms fa
    LEFT JOIN aki_flags af USING (hadm_id)
  WHERE
    af.aki_flag_rank IN (1,2)
),

-- 4) imaging hcpcs events (restrict to rows likely representing radiology/imaging)
imaging_hcpcs AS (
  SELECT
    h.hadm_id,
    h.chartdate,
    COALESCE(d.long_description, '') AS long_description,
    COALESCE(h.short_description, '') AS short_description,
    LOWER(CONCAT(COALESCE(d.long_description, ''), ' ', COALESCE(h.short_description, ''))) AS txt
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    h.chartdate IS NOT NULL
    -- keyword-based filter for imaging/radiology procedures
    AND (
      LOWER(COALESCE(d.long_description, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%radiography%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%computed tomograph%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '% ct %'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '% ct'
      OR LOWER(COALESCE(d.long_description, '')) LIKE 'ct %'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%mri%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%magnetic resonance%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%ultrasound%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%sonograph%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%x-ray%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%xray%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%fluoroscop%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%angiograph%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%nuclear%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%pet%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%spect%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%mammograph%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%echocardi%'
      -- also check the short_description field
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%ct%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%mri%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%ultrasound%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%x-ray%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%xray%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%fluoro%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%angio%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%pet%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%mammog%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%echo%'
    )
),

-- 5) counts of imaging events per admission in the two windows (day 1-3 and day 4-7)
imaging_counts_per_adm AS (
  -- start with cohort (ensures we include admissions with zero imaging)
  SELECT
    c.hadm_id,
    c.aki_class,
    -- count imaging in day 1-3
    COALESCE(SUM(CASE WHEN oday.day_index BETWEEN 1 AND 3 THEN 1 ELSE 0 END), 0) AS cnt_day_1_3,
    -- count imaging in day 4-7
    COALESCE(SUM(CASE WHEN oday.day_index BETWEEN 4 AND 7 THEN 1 ELSE 0 END), 0) AS cnt_day_4_7
  FROM
    cohort c
    LEFT JOIN (
      -- compute day index per imaging event relative to admission
      SELECT
        ih.hadm_id,
        ih.chartdate,
        DATE_DIFF(DATE(ih.chartdate), DATE(a.admittime), DAY) + 1 AS day_index
      FROM
        imaging_hcpcs ih
        JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
          ON ih.hadm_id = a.hadm_id
      -- note: we join to admissions to get admittime for accurate day index
    ) oday
      ON c.hadm_id = oday.hadm_id
  GROUP BY
    c.hadm_id,
    c.aki_class
),

-- 6) unpivot counts so we can compute quantiles per window x aki_class
per_adm_unpivot AS (
  SELECT hadm_id, aki_class, 'day_1_to_3' AS window_label, cnt_day_1_3 AS cnt FROM imaging_counts_per_adm
  UNION ALL
  SELECT hadm_id, aki_class, 'day_4_to_7' AS window_label, cnt_day_4_7 AS cnt FROM imaging_counts_per_adm
)

-- Final: compute approximate median and IQR (25th & 75th pct) per group
SELECT
  aki_class AS aki_classification,
  window_label AS window_label,
  -- APPROX_QUANTILES returns an array; we select approximate percentiles at offsets 25/50/75
  APPROX_QUANTILES(cnt, 100)[OFFSET(50)] AS approx_median,
  APPROX_QUANTILES(cnt, 100)[OFFSET(25)] AS approx_p25,
  APPROX_QUANTILES(cnt, 100)[OFFSET(75)] AS approx_p75,
  COUNT(*) AS n_admissions
FROM
  per_adm_unpivot
GROUP BY
  aki_class,
  window_label
ORDER BY
  aki_classification,
  window_label;