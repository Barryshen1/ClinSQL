WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hospital_expire_flag = 0
),
dx AS (
  SELECT DISTINCT
    hadm_id,
    MAX(CASE WHEN icd_code LIKE '250%' THEN 1 ELSE 0 END)     AS has_diabetes,
    MAX(CASE WHEN icd_code LIKE '428%' THEN 1 ELSE 0 END)     AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
base_cohort AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    JOIN dx
      ON c.hadm_id = dx.hadm_id
  WHERE
    dx.has_diabetes = 1
    AND dx.has_hf = 1
),
med_classes AS (
  SELECT 'antidiabetic'   AS class, '%metformin%'   AS pattern UNION ALL
  SELECT 'antidiabetic'   AS class, '%insulin%'     AS pattern UNION ALL
  SELECT 'beta_blocker'   AS class, '%propranolol%' UNION ALL
  SELECT 'beta_blocker'   AS class, '%metoprolol%'  UNION ALL
  SELECT 'beta_blocker'   AS class, '%atenolol%'   UNION ALL
  SELECT 'ace_arb_arni'   AS class, '%lisinopril%' UNION ALL
  SELECT 'ace_arb_arni'   AS class, '%losartan%'   UNION ALL
  SELECT 'ace_arb_arni'   AS class, '%valsartan%'  UNION ALL
  SELECT 'ace_arb_arni'   AS class, '%sacubitril%' UNION ALL
  SELECT 'loop_diuretic'  AS class, '%furosemide%' UNION ALL
  SELECT 'loop_diuretic'  AS class, '%bumetanide%' UNION ALL
  SELECT 'loop_diuretic'  AS class, '%torsemide%'
),
med_exposures AS (
  SELECT
    bc.hadm_id,
    mc.class,
    -- first 24h overlap
    MAX(CASE WHEN pr.starttime < TIMESTAMP_ADD(bc.admittime, INTERVAL 24 HOUR)
              AND pr.stoptime > bc.admittime THEN 1 ELSE 0 END
       ) AS on_first24,
    -- last 24h overlap
    MAX(CASE WHEN pr.starttime < bc.dischtime
              AND pr.stoptime > TIMESTAMP_SUB(bc.dischtime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END
       ) AS on_last24
  FROM
    base_cohort bc
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON bc.hadm_id = pr.hadm_id
    JOIN med_classes mc
      ON LOWER(pr.drug) LIKE mc.pattern
  GROUP BY
    bc.hadm_id,
    mc.class
),
status_flags AS (
  SELECT
    class,
    CASE
      WHEN on_first24 = 1 AND on_last24 = 1 THEN 'continued'
      WHEN on_first24 = 0 AND on_last24 = 1 THEN 'initiated_late'
      WHEN on_first24 = 1 AND on_last24 = 0 THEN 'discontinued'
      ELSE 'other'
    END AS status
  FROM
    med_exposures
),
totals AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_hadm
  FROM base_cohort
)
SELECT
  sf.class,
  sf.status,
  COUNT(*)                           AS count_hadm,
  ROUND(100.0 * COUNT(*) / t.total_hadm, 2) AS pct_of_cohort
FROM
  status_flags sf
  CROSS JOIN totals t
WHERE
  sf.status IN ('continued','initiated_late','discontinued')
GROUP BY
  sf.class,
  sf.status,
  t.total_hadm
ORDER BY
  sf.class,
  sf.status;