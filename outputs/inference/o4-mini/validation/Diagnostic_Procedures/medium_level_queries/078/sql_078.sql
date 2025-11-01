WITH tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE '435%' OR d.icd_code LIKE 'G45%'
),
eligible_admissions AS (
  SELECT
    t.*
  FROM
    tia_admissions AS t
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON t.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND t.los_days BETWEEN 1 AND 7
),
admissions_with_icu AS (
  SELECT
    e.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
      WHERE i.hadm_id = e.hadm_id
    ) AS icu_use
  FROM
    eligible_admissions AS e
),
imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT h.seq_num) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d
    ON h.hcpcs_cd = d.code
  WHERE
    LOWER(d.long_description) LIKE '%ct%'
    OR LOWER(d.long_description) LIKE '%mri%'
  GROUP BY
    h.hadm_id
),
bucketed AS (
  SELECT
    a.hadm_id,
    a.los_days,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3'
      ELSE '4-7'
    END AS stay_group,
    a.icu_use
  FROM
    admissions_with_icu AS a
)
SELECT
  stats.stay_group,
  stats.icu_use,
  stats.qt[OFFSET(1)] AS q1_ct_mri,
  stats.qt[OFFSET(2)] AS median_ct_mri,
  stats.qt[OFFSET(3)] AS q3_ct_mri
FROM (
  SELECT
    b.stay_group,
    b.icu_use,
    APPROX_QUANTILES(COALESCE(ic.imaging_count, 0), 4) AS qt
  FROM
    bucketed AS b
  LEFT JOIN
    imaging_counts AS ic
  ON
    b.hadm_id = ic.hadm_id
  GROUP BY
    b.stay_group,
    b.icu_use
) AS stats
ORDER BY
  stats.stay_group,
  stats.icu_use;