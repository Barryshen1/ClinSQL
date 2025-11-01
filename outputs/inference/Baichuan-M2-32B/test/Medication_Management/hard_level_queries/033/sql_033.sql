WITH
  eligible_patients AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND TIMESTAMP_DIFF(a.admittime, TIMESTAMP(CONCAT(CAST(p.anchor_year AS STRING), '-01-01')), YEAR) BETWEEN 80 AND 90
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE
          d.hadm_id = a.hadm_id
          AND d.icd_version = 10
          AND (dd.icd_code LIKE 'A40%' OR dd.icd_code LIKE 'A41%')
      )
  ),
  med_orders_24h AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      COUNT(DISTINCT pr.drug) AS med_complexity_score
    FROM
      eligible_patients e
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON e.subject_id = pr.subject_id AND e.hadm_id = pr.hadm_id
    WHERE
      pr.starttime BETWEEN e.admittime AND e.admittime + INTERVAL 24 HOUR
    GROUP BY
      e.subject_id, e.hadm_id
  ),
  qt_drugs AS (
    SELECT 'amiodarone' AS drug_name
    UNION ALL SELECT 'quinidine'
    UNION ALL SELECT 'sotalol'
    UNION ALL SELECT 'dofetilide'
    UNION ALL SELECT 'ibutilide'
    UNION ALL SELECT 'disopyramide'
    UNION ALL SELECT 'procainamide'
    UNION ALL SELECT 'haloperidol'
    UNION ALL SELECT 'thioridazine'
    UNION ALL SELECT 'mesoridazine'
    UNION ALL SELECT 'pimozide'
    UNION ALL SELECT 'dronedarone'
    UNION ALL SELECT 'vandetanib'
    UNION ALL SELECT 'aranesp'
    UNION ALL SELECT 'domperidone'
    UNION ALL SELECT 'ondansetron'
    UNION ALL SELECT 'citalopram'
    UNION ALL SELECT 'escitalopram'
    UNION ALL SELECT 'levofloxacin'
    UNION ALL SELECT 'moxifloxacin'
    UNION ALL SELECT 'troglitazone'
    UNION ALL SELECT 'halothane'
    UNION ALL SELECT 'pentobarbital'
    UNION ALL SELECT 'clozapine'
  ),
  bleeding_risk_drugs AS (
    SELECT 'warfarin' AS drug_name
    UNION ALL SELECT 'heparin'
    UNION ALL SELECT 'enoxaparin'
    UNION ALL SELECT 'dalteparin'
    UNION ALL SELECT 'fondaparinux'
    UNION ALL SELECT 'aspirin'
    UNION ALL SELECT 'clopidogrel'
    UNION ALL SELECT 'ticagrelor'
    UNION ALL SELECT 'prasugrel'
    UNION ALL SELECT 'dabigatran'
    UNION ALL SELECT 'rivaroxaban'
    UNION ALL SELECT 'apixaban'
    UNION ALL SELECT 'edoxaban'
    UNION ALL SELECT 'desmopressin'
    UNION ALL SELECT 'abciximab'
    UNION ALL SELECT 'tirofiban'
    UNION ALL SELECT 'eptifibatide'
    UNION ALL SELECT 'bivalirudin'
    UNION ALL SELECT 'fondaparinux'
    UNION ALL SELECT 'danaparoid'
    UNION ALL SELECT 'hirudin'
    UNION ALL SELECT 'lepirudin'
    UNION ALL SELECT 'argatroban'
    UNION ALL SELECT 'fondaparinux'
  ),
  drug_flags AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      MAX(CASE WHEN pr.drug IN (SELECT drug_name FROM qt_drugs) THEN 1 ELSE 0 END) AS has_qt_prolonging,
      MAX(CASE WHEN pr.drug IN (SELECT drug_name FROM bleeding_risk_drugs) THEN 1 ELSE 0 END) AS has_bleeding_risk
    FROM
      eligible_patients e
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON e.subject_id = pr.subject_id AND e.hadm_id = pr.hadm_id
    WHERE
      pr.starttime BETWEEN e.admittime AND e.admittime + INTERVAL 24 HOUR
    GROUP BY
      e.subject_id, e.hadm_id
  ),
  patient_scores AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.admittime,
      e.dischtime,
      e.hospital_expire_flag,
      COALESCE(m.med_complexity_score, 0) AS med_complexity_score,
      d.has_qt_prolonging,
      d.has_bleeding_risk,
      CASE WHEN d.has_qt_prolonging = 1 AND d.has_bleeding_risk = 1 THEN 1 ELSE 0 END AS is_high_risk
    FROM
      eligible_patients e
    LEFT JOIN
      med_orders_24h m
      ON e.subject_id = m.subject_id AND e.hadm_id = m.hadm_id
    LEFT JOIN
      drug_flags d
      ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
  ),
  with_percentiles AS (
    SELECT
      *,
      PERCENT_RANK() OVER (ORDER BY med_complexity_score) AS percentile_rank
    FROM
      patient_scores
  ),
  top_quartile AS (
    SELECT
      *
    FROM
      with_percentiles
    WHERE
      percentile_rank >= 0.75
  )
SELECT
  t.subject_id,
  t.hadm_id,
  t.med_complexity_score,
  t.percentile_rank,
  t.is_high_risk,
  TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY) AS los,
  t.hospital_expire_flag AS mortality
FROM
  top_quartile t;