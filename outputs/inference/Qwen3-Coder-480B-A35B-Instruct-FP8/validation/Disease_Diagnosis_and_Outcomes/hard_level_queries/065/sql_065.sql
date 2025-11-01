with dvt_cohort as (
  select distinct
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    a.hospital_expire_flag,
    icu.los as icu_los,
    date_diff(cast(a.dischtime as date), cast(a.admittime as date), day) as hosp_los,
    case
      when p.dod is not null and p.dod <= datetime_add(a.admittime, interval 90 day) then 1
      else 0
    end as died_within_90_days,
    case
      when p.dod is null or p.dod > a.dischtime then 1
      else 0
    end as survived_hosp,
    drg.drg_severity
  from physionet-data.mimiciv_3_1_hosp.admissions a
  join physionet-data.mimiciv_3_1_hosp.patients p on a.subject_id = p.subject_id
  join physionet-data.mimiciv_3_1_hosp.diagnoses_icd d on a.hadm_id = d.hadm_id
  join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd on d.icd_code = d_icd.icd_code and d.icd_version = d_icd.icd_version
  left join physionet-data.mimiciv_3_1_hosp.drgcodes drg on a.hadm_id = drg.hadm_id
  left join physionet-data.mimiciv_3_1_icu.icustays icu on a.hadm_id = icu.hadm_id
  where
    p.gender = 'M'
    and p.anchor_age between 71 and 81
    and lower(d_icd.long_title) like '%deep vein thrombosis%'
    and drg.drg_severity = 4
),

complications as (
  select distinct
    d.hadm_id
  from physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    on d.icd_code = d_icd.icd_code and d.icd_version = d_icd.icd_version
  where lower(d_icd.long_title) like '%hemorrhage%' or lower(d_icd.long_title) like '%bleeding%'
),

dvt_with_complications as (
  select
    dvt.*,
    case when c.hadm_id is not null then 1 else 0 end as had_complication
  from dvt_cohort dvt
  left join complications c on dvt.hadm_id = c.hadm_id
),

general_inpatients as (
  select
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    a.hospital_expire_flag,
    date_diff(cast(a.dischtime as date), cast(a.admittime as date), day) as hosp_los,
    case
      when p.dod is not null and p.dod <= datetime_add(a.admittime, interval 90 day) then 1
      else 0
    end as died_within_90_days,
    case
      when p.dod is null or p.dod > a.dischtime then 1
      else 0
    end as survived_hosp
  from physionet-data.mimiciv_3_1_hosp.admissions a
  join physionet-data.mimiciv_3_1_hosp.patients p on a.subject_id = p.subject_id
  where p.gender = 'M' and p.anchor_age between 71 and 81
),

dvt_stats as (
  select
    approx_quantiles(drg_severity, 100)[offset(50)] as median_risk,
    approx_quantiles(drg_severity, 100)[offset(25)] as q1_risk,
    approx_quantiles(drg_severity, 100)[offset(75)] as q3_risk,
    avg(drg_severity) as mean_risk,
    avg(cast(died_within_90_days as float64)) as mortality_90,
    avg(cast(had_complication as float64)) as complication_rate,
    avg(case when survived_hosp = 1 then hosp_los else null end) as mean_survivor_los,
    count(*) as n_dvt
  from dvt_with_complications
),

general_stats as (
  select
    avg(cast(died_within_90_days as float64)) as gen_mortality_90,
    avg(case when survived_hosp = 1 then hosp_los else null end) as gen_mean_survivor_los
  from general_inpatients
)

select
  ds.median_risk,
  ds.q1_risk,
  ds.q3_risk,
  ds.mortality_90,
  ds.complication_rate,
  ds.mean_survivor_los,
  gs.gen_mortality_90,
  gs.gen_mean_survivor_los,
  percentile_cont(ds.mean_risk, 0.5) over() as risk_percentile
from dvt_stats ds
cross join general_stats gs;