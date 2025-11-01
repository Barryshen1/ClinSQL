WITH
  -- Step 1: Define the cohort of female, multi-trauma patients aged 68-78
  multi_trauma_hadm AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    WHERE
      LOWER(d.long_title) LIKE '%multiple injuries%'
  ),

  cohort AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    -- Inner join to filter for only multi-trauma patients
    JOIN multi_trauma_hadm AS mt
      ON adm.hadm_id = mt.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 68 AND 78
  ),

  -- Step 2: Get all prescriptions within the first 24 hours of admission for the cohort
  meds_first_24h AS (
    SELECT
      c.hadm_id,
      pres.drug
    FROM cohort AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
      ON c.hadm_id = pres.hadm_id
    WHERE
      pres.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  ),

  -- Define a list of serotonergic drugs
  serotonergic_drug_list AS (
    SELECT drug_name FROM UNNEST([
      'fluoxetine', 'sertraline', 'citalopram', 'escitalopram', 'paroxetine', 'fluvoxamine',
      'venlafaxine', 'duloxetine', 'desvenlafaxine', 'levomilnacipran',
      'amitriptyline', 'nortriptyline', 'imipramine', 'clomipramine', 'doxepin',
      'phenelzine', 'tranylcypromine', 'isocarboxazid', 'selegiline',
      'trazodone', 'mirtazapine', 'buspirone', 'vilazodone',
      'tramadol', 'fentanyl', 'meperidine', 'methadone', 'tapentadol',
      'ondansetron', 'granisetron', 'palonosetron',
      'sumatriptan', 'rizatriptan', 'eletriptan',
      'linezolid', 'methylene blue', 'lithium'
    ]) AS drug_name
  ),

  -- Step 3: Flag each unique medication as serotonergic or not
  meds_first_24h_flagged AS (
    SELECT
      m.hadm_id,
      m.drug,
      -- A drug might match multiple patterns (e.g., 'fentanyl' and a specific formulation)
      -- MAX ensures we get a single 1 or 0 flag per drug.
      MAX(CASE WHEN sdl.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS is_serotonergic
    FROM (SELECT DISTINCT hadm_id, drug FROM meds_first_24h) AS m
    LEFT JOIN serotonergic_drug_list AS sdl
      ON LOWER(m.drug) LIKE '%' || sdl.drug_name || '%'
    GROUP BY m.hadm_id, m.drug
  ),

  -- Calculate total and serotonergic medication counts for each patient
  patient_med_counts AS (
    SELECT
      hadm_id,
      COUNT(drug) AS total_med_count,
      SUM(is_serotonergic) AS serotonergic_med_count
    FROM meds_first_24h_flagged
    GROUP BY hadm_id
  ),

  -- Step 4: Combine patient data with med counts and calculate outcomes/metrics
  patient_stats_raw AS (
    SELECT
      c.hadm_id,
      c.hospital_expire_flag,
      DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
      COALESCE(pmc.total_med_count, 0) AS med_count,
      CASE WHEN COALESCE(pmc.serotonergic_med_count, 0) >= 2 THEN 1 ELSE 0 END AS has_serotonergic_risk
    FROM cohort AS c
    LEFT JOIN patient_med_counts AS pmc
      ON c.hadm_id = pmc.hadm_id
  ),

  -- Calculate percent rank for medication complexity
  patient_stats_final AS (
    SELECT
      *,
      PERCENT_RANK() OVER (ORDER BY med_count) AS med_complexity_percentile
    FROM patient_stats_raw
  ),

  -- Calculate complexity quartiles for the entire cohort
  quartiles AS (
    SELECT APPROX_QUANTILES(med_count, 4) AS med_count_quartiles
    FROM patient_stats_final
  ),

  -- Step 5: Generate the final report by grouping and summarizing
  grouped_stats AS (
    -- Group 1: Patients WITH serotonergic interaction risk
    SELECT
      'Serotonergic Interaction Risk' AS patient_group,
      COUNT(hadm_id) AS patient_count,
      AVG(los_days) AS avg_los_days,
      AVG(hospital_expire_flag) AS mortality_rate,
      AVG(med_complexity_percentile) AS avg_med_complexity_percentile
    FROM patient_stats_final
    WHERE has_serotonergic_risk = 1

    UNION ALL

    -- Group 2: Patients WITHOUT serotonergic interaction risk
    SELECT
      'Other Multi-Trauma Patients' AS patient_group,
      COUNT(hadm_id) AS patient_count,
      AVG(los_days) AS avg_los_days,
      AVG(hospital_expire_flag) AS mortality_rate,
      AVG(med_complexity_percentile) AS avg_med_complexity_percentile
    FROM patient_stats_final
    WHERE has_serotonergic_risk = 0

    UNION ALL

    -- Group 3: Patients in the TOP QUARTILE of medication complexity
    SELECT
      'Top Quartile Medication Complexity' AS patient_group,
      COUNT(hadm_id) AS patient_count,
      AVG(los_days) AS avg_los_days,
      AVG(hospital_expire_flag) AS mortality_rate,
      AVG(med_complexity_percentile) AS avg_med_complexity_percentile
    FROM patient_stats_final
    -- Top quartile is defined as having a med_count > the 3rd quartile value (75th percentile)
    WHERE med_count > (SELECT med_count_quartiles[OFFSET(3)] FROM quartiles)
)

-- Final SELECT to combine aggregated stats with the overall quartiles
SELECT
  gs.patient_group,
  gs.patient_count,
  gs.avg_los_days,
  gs.mortality_rate,
  gs.avg_med_complexity_percentile,
  q.med_count_quartiles[OFFSET(1)] AS medication_complexity_q1,
  q.med_count_quartiles[OFFSET(2)] AS medication_complexity_median,
  q.med_count_quartiles[OFFSET(3)] AS medication_complexity_q3
FROM grouped_stats AS gs, quartiles AS q
ORDER BY gs.patient_group;